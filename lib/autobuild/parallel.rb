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
                tic = nil
                while true
                    @rio.read(token_count)
                    toc = Time.now

                    return if tic && (toc - tic) < 0.1

                    tic = toc
                    put(token_count)
                    sleep 0.01
                end
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

        def discover_dependencies(all_tasks, reverse_dependencies, t)
            if t.already_invoked?
                return 
            end

            return if all_tasks.include?(t) # already discovered or being discovered
            all_tasks << t

            t.prerequisite_tasks.each do |dep_t|
                reverse_dependencies[dep_t] << t
                discover_dependencies(all_tasks, reverse_dependencies, dep_t)
            end
        end

        class ProcessingState
            attr_reader :reverse_dependencies
            attr_reader :processed
            attr_reader :active_tasks
            attr_reader :queue
            attr_reader :priorities

            def initialize(reverse_dependencies, weights: Hash.new(0))
                @reverse_dependencies = reverse_dependencies
                @processed = Set.new
                @active_tasks = Set.new
                @priorities = Hash.new
                @queue = Array.new
                @weights = weights
            end

            def push(task)
                @queue.unshift(task)
                @queue = @queue.sort_by { |t| @weights[t] }
            end

            def find_task
                @queue.last
            end

            def top
                @queue.last
            end

            def queue_empty?
                @queue.empty?
            end

            def pop
                @queue.pop
            end

            def weight_of(task)
                @weights[task]
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
                        push(candidate)
                    end
                end
            end

            def trivial_task?(task)
                (task.kind_of?(Rake::Task) || task.kind_of?(Autobuild::SourceTreeTask) || task.kind_of?(Rake::FileTask)) &&
                    task.actions.empty?
            end
        end

        def compute_weights(tasks, reverse_dependencies)
            all_downstream = Hash.new
            queue = Array.new
            wait_count = Hash.new 
            tasks.each do |t|
                revdep = reverse_dependencies[t]
                wait = revdep.size
                all_downstream[t] = revdep.
                    map { |t| t.package if t.respond_to?(:package) }.
                    compact.to_set
                if wait == 0
                    queue << t
                else
                    wait_count[t] = wait
                end
            end

            until queue.empty?
                t = queue.shift
                t.prerequisite_tasks.each do |pre_t|
                    all_downstream[pre_t].merge(all_downstream[t])
                    new_count = (wait_count[pre_t] -= 1)
                    if new_count == 0
                        wait_count.delete(pre_t)
                        queue << pre_t 
                    end
                end
            end

            unless wait_count.empty?
                raise "internal inconsistency in weight calculations"
            end

            all_downstream.each_with_object(Hash.new) do |(t, set), w|
                w[t] = set.size
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
            weights = compute_weights(tasks, reverse_dependencies)

            # The queue is the set of tasks for which all prerequisites have
            # been successfully executed (or where not needed). I.e. it is the
            # set of tasks that can be queued for execution.
            state = ProcessingState.new(reverse_dependencies, weights: weights)
            tasks.each do |t|
                if state.ready?(t)
                    state.push(t)
                end
            end
            
            # Build a reverse dependency graph (i.e. a mapping from a task to
            # the tasks that depend on it)

            # This is kind-of a topological sort. However, we don't do the full
            # topological sort since we would then have to scan all tasks each
            # time for tasks that have no currently running prerequisites

            while true
                pending_task = state.pop
                if !pending_task
                    # If we have pending workers, wait for one to be finished
                    # until either they are all finished or the queue is not
                    # empty anymore
                    while !pending_task && available_workers.size != workers.size
                        wait_for_worker_to_end(state)
                        pending_task = state.pop
                    end

                    if !pending_task && available_workers.size == workers.size
                        break
                    end
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

                while !finished_workers.empty?
                    wait_for_worker_to_end(state)
                end

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
            if !not_processed.empty?
                cycle = resolve_cycle(tasks, not_processed, reverse_dependencies)
                raise "cycle in task graph: #{cycle.map(&:name).sort.join(", ")}"
            end
        end

        def resolve_cycle(all_tasks, tasks, reverse_dependencies)
            cycle = tasks.dup
            chain = []
            next_task = tasks.first
            while true
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
                if !next_task
                    Autobuild.fatal "parallel processing stopped prematurely, but no cycle is present in the remaining tasks"
                    Autobuild.fatal "remaining tasks: #{cycle.map(&:name).join(", ")}"
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
                    raise "failed to resolve cycle in #{cycle.map(&:name).join(", ")}"
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
                return @last_finished_task, @last_error
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


