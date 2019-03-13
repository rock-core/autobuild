require 'thread'

module Autobuild
    # This is a rewrite of the Rake task invocation code to use parallelism
    #
    # Since autobuild does not use task arguments, we don't support them for
    # simplicity
    class RakeTaskParallelism
        attr_reader :available_workers
        attr_reader :finished_workers
        attr_reader :workers

        attr_reader :job_server

        class JobServer
            attr_reader :rio
            attr_reader :wio

            def initialize(level)
                @rio, @wio = IO.pipe
                # Clearing cloexec
                rio.fcntl(Fcntl::F_SETFD, 0)
                wio.fcntl(Fcntl::F_SETFD, 0)
                put(level)
            end

            def get(token_count = 1)
                @rio.read(token_count)
            end

            def put(token_count = 1)
                @wio.write(" " * token_count)
            end
        end

        def initialize(level = Autobuild.parallel_build_level)
            @job_server = JobServer.new(level)
            @available_workers = Array.new
            @finished_workers = Queue.new
            @workers = Array.new
        end

        def wait_for_worker_to_end(state)
            w = finished_workers.pop
            finished_task, error = w.last_result
            available_workers << w
            if error
                if available_workers.size != workers.size
                    if finished_task.respond_to?(:package) && finished_task.package
                        Autobuild.error "got an error processing #{finished_task.package.name}, waiting for pending jobs to end"
                    else
                        Autobuild.error "got an error doing parallel processing, waiting for pending jobs to end"
                    end
                end
                begin
                    finish_pending_work
                ensure
                    raise error
                end
            end

            state.process_finished_task(finished_task)
        end

        def discover_dependencies(all_tasks, reverse_dependencies, task)
            return if task.already_invoked?
            return if all_tasks.include?(task) # already discovered or being discovered
            all_tasks << task

            task.prerequisite_tasks.each do |dep_t|
                reverse_dependencies[dep_t] << task
                discover_dependencies(all_tasks, reverse_dependencies, dep_t)
            end
        end

        class ProcessingState
            attr_reader :reverse_dependencies
            attr_reader :processed
            attr_reader :started_packages
            attr_reader :active_tasks
            attr_reader :queue
            attr_reader :priorities

            def initialize(reverse_dependencies)
                @reverse_dependencies = reverse_dependencies
                @processed = Set.new
                @active_tasks = Set.new
                @priorities = Hash.new
                @started_packages = Hash.new
                @queue = Hash.new
            end

            def push(task, base_priority = 1)
                if task.respond_to?(:package)
                    started_packages[task.package] ||= -started_packages.size
                    queue[task] = started_packages[task.package]
                else queue[task] = base_priority
                end
            end

            def find_task
                if (task = queue.min_by { |_t, p| p })
                    priorities[task.first] = task.last
                    task.first
                end
            end

            def pop
                candidate = find_task
                queue.delete(candidate)
                candidate
            end

            def mark_as_active(pending_task)
                active_tasks << pending_task
            end

            def active_task?(task)
                active_tasks.include?(task)
            end

            def ready?(task)
                task.prerequisite_tasks.all? do |t|
                    already_processed?(t)
                end
            end

            def already_processed?(task)
                task.already_invoked? && !active_task?(task)
            end

            def needs_processing?(task)
                !task.already_invoked? && !active_task?(task)
            end

            def process_finished_task(task)
                active_tasks.delete(task)
                processed << task
                reverse_dependencies[task].each do |candidate|
                    if needs_processing?(candidate) && ready?(candidate)
                        push(candidate, priorities[task])
                    end
                end
            end

            def trivial_task?(task)
                (task.kind_of?(Autobuild::SourceTreeTask) || task.kind_of?(Rake::FileTask)) && task.actions.empty?
            end
        end

        # Invokes the provided tasks. Unlike the rake code, this is a toplevel
        # algorithm that does not use recursion
        def invoke_parallel(required_tasks)
            tasks = Set.new
            reverse_dependencies = Hash.new { |h, k| h[k] = Set.new }
            required_tasks.each do |t|
                discover_dependencies(tasks, reverse_dependencies, t)
            end
            # The queue is the set of tasks for which all prerequisites have
            # been successfully executed (or where not needed). I.e. it is the
            # set of tasks that can be queued for execution.
            state = ProcessingState.new(reverse_dependencies)
            tasks.each do |t|
                state.push(t) if state.ready?(t)
            end

            # Build a reverse dependency graph (i.e. a mapping from a task to
            # the tasks that depend on it)

            # This is kind-of a topological sort. However, we don't do the full
            # topological sort since we would then have to scan all tasks each
            # time for tasks that have no currently running prerequisites

            loop do
                pending_task = state.pop
                unless pending_task
                    # If we have pending workers, wait for one to be finished
                    # until either they are all finished or the queue is not
                    # empty anymore
                    while !pending_task && available_workers.size != workers.size
                        wait_for_worker_to_end(state)
                        pending_task = state.pop
                    end

                    break if !pending_task && available_workers.size == workers.size
                end

                if state.trivial_task?(pending_task)
                    Worker.execute_task(pending_task)
                    state.process_finished_task(pending_task)
                    next
                elsif pending_task.already_invoked? || !pending_task.needed?
                    pending_task.already_invoked = true
                    state.process_finished_task(pending_task)
                    next
                end

                # Get a job server token
                job_server.get

                wait_for_worker_to_end(state) until finished_workers.empty?

                # We do have a job server token, so we are allowed to allocate a
                # new worker if none are available
                if available_workers.empty?
                    w = Worker.new(job_server, finished_workers)
                    available_workers << w
                    workers << w
                end

                worker = available_workers.pop
                state.mark_as_active(pending_task)
                worker.queue(pending_task)
            end

            not_processed = tasks.find_all { |t| !t.already_invoked? }
            unless not_processed.empty?
                cycle = resolve_cycle(tasks, not_processed, reverse_dependencies)
                raise "cycle in task graph: #{cycle.map(&:name).sort.join(', ')}"
            end
        end

        def resolve_cycle(all_tasks, tasks, reverse_dependencies)
            cycle = tasks.dup
            chain = []
            next_task = tasks.first
            loop do
                task = next_task
                chain << task
                tasks.delete(next_task)
                next_task = task.prerequisite_tasks.find do |dep_task|
                    if chain.include?(dep_task)
                        reject = chain.take_while { |t| t != dep_task }
                        return chain[reject.size..-1]
                    elsif tasks.include?(dep_task)
                        true
                    end
                end
                unless next_task
                    Autobuild.fatal "parallel processing stopped prematurely, but no cycle is present in the remaining tasks"
                    Autobuild.fatal "remaining tasks: #{cycle.map(&:name).join(', ')}"
                    Autobuild.fatal "known dependencies at initialization time that could block the processing of the remaining tasks"
                    reverse_dependencies.each do |parent_task, parents|
                        if cycle.include?(parent_task)
                            parents.each do |p|
                                Autobuild.fatal "  #{p}: #{parent_task}"
                            end
                        end
                    end
                    Autobuild.fatal "known dependencies right now that could block the processing of the remaining tasks"
                    all_tasks.each do |p|
                        (cycle & p.prerequisite_tasks).each do |t|
                            Autobuild.fatal "  #{p}: #{t}"
                        end
                    end
                    raise "failed to resolve cycle in #{cycle.map(&:name).join(', ')}"
                end
            end
            chain
        end

        class Worker
            attr_reader :job_server

            def initialize(job_server, finished_workers)
                @job_server = job_server
                @finished_workers = finished_workers
                @input = Queue.new
                @thread = Thread.new do
                    loop do
                        task = @input.pop
                        do_task(task)
                    end
                end
            end

            def self.execute_task(task)
                task_args = Rake::TaskArguments.new(task.arg_names, [])
                task.instance_variable_set(:@already_invoked, true)
                task.send(:execute, task_args)
            end

            def do_task(task)
                @last_error = nil
                Worker.execute_task(task)
                @last_finished_task = task
            rescue ::Exception => e
                @last_finished_task = task
                @last_error = e
            ensure
                job_server.put
                @finished_workers.push(self)
            end

            def last_result
                [@last_finished_task, @last_error]
            end

            def queue(task)
                @input.push(task)
            end
        end

        def finish_pending_work
            while available_workers.size != workers.size
                w = finished_workers.pop
                available_workers << w
            end
        end
    end

    class << self
        attr_accessor :parallel_task_manager
    end
end
