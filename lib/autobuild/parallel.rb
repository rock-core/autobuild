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
                    Autobuild.error "got an error doing parallel processing, waiting for pending jobs to end"
                end
                finish_pending_work
                raise error
            end

            state.process_finished_task(finished_task)
        end

        def discover_dependencies(all_tasks, reverse_dependencies, t)
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
            attr_reader :started_packages
            attr_reader :active_packages
            attr_reader :queue

            def initialize(reverse_dependencies, initial_queue = Array.new)
                @reverse_dependencies = reverse_dependencies
                @processed = Set.new
                @active_packages = Set.new
                @started_packages = Set.new
                @queue = initial_queue.to_set
            end

            def find_task
                possible_task = nil
                queue.each do |task|
                    if task.respond_to?(:package)
                        if !active_packages.include?(task.package)
                            if started_packages.include?(task.package)
                                return task
                            end
                            possible_task ||= task
                        end
                    else possible_task ||= task
                    end
                end
                possible_task
            end

            def pop
                candidate = find_task
                queue.delete(candidate)
                candidate
            end

            def mark_as_active(pending_task)
                if pending_task.respond_to?(:package)
                    active_packages << pending_task.package
                    started_packages << pending_task.package
                end
            end

            def process_finished_task(task)
                if task.respond_to?(:package)
                    active_packages.delete(task.package)
                end
                processed << task
                reverse_dependencies[task].each do |candidate|
                    if candidate.prerequisite_tasks.all? { |t| processed.include?(t) }
                        queue << candidate
                    end
                end
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
            roots = tasks.find_all { |t| t.prerequisite_tasks.empty? }.to_set
            
            # Build a reverse dependency graph (i.e. a mapping from a task to
            # the tasks that depend on it)

            # This is kind-of a topological sort. However, we don't do the full
            # topological sort since we would then have to scan all tasks each
            # time for tasks that have no currently running prerequisites

            # The queue is the set of tasks for which all prerequisites have
            # been successfully executed (or where not needed). I.e. it is the
            # set of tasks that can be queued for execution.
            state = ProcessingState.new(reverse_dependencies, roots.to_a)
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

                if pending_task.instance_variable_get(:@already_invoked) || !pending_task.needed?
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

            if state.processed.size != tasks.size
                with_cycle = tasks.to_set
                raise "cycle in task graph: #{with_cycle.map(&:name).sort.join(", ")}"
            end
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

            def do_task(task)
                @last_error = nil
                task_args = Rake::TaskArguments.new(task.arg_names, [])
                task.instance_variable_set(:@already_invoked, true)
                task.send(:execute, task_args)
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


