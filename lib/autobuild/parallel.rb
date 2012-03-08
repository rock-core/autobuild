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

        attr_reader :roots
        attr_reader :tasks
        attr_reader :reverse_dependencies

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

        def process_finished_task(task, processed, queue)
            processed << task
            #puts "finished #{task} (#{task.object_id}), considering dependencies"
            reverse_dependencies[task].each do |candidate|
                if candidate.prerequisite_tasks.all? { |t| processed.include?(t) }
                    #puts "  adding #{candidate}"
                    queue << candidate
                else
                    #puts "  rejecting #{candidate} (#{candidate.prerequisite_tasks.find_all { |t| !processed.include?(t) }.map(&:name).join(", ")})"
                end
            end
        end

        def wait_for_worker_to_end(processed, queue)
            w = finished_workers.pop
            finished_task, error = w.last_result
            available_workers << w
            if error
                if available_workers.size != workers.size
                    Autobuild.message "got an error doing parallel processing, waiting for pending jobs to end"
                end
                finish_pending_work
                raise error
            end

            process_finished_task(finished_task, processed, queue)
        end

        def discover_dependencies(t)
            return if tasks.include?(t) # already discovered or being discovered
            #puts "adding #{t}"
            tasks << t

            t.prerequisite_tasks.each do |dep_t|
                reverse_dependencies[dep_t] << t
                discover_dependencies(dep_t)
            end
        end

        # Invokes the provided tasks. Unlike the rake code, this is a toplevel
        # algorithm that does not use recursion
        def invoke_parallel(required_tasks)
            @tasks = Set.new
            @reverse_dependencies = Hash.new { |h, k| h[k] = Set.new }
            required_tasks.each do |t|
                discover_dependencies(t)
            end
            @roots = tasks.find_all { |t| t.prerequisite_tasks.empty? }.to_set

            #puts "roots:"
            roots.each do |t|
                #puts "  #{t}"
            end
            #puts
            
            # Build a reverse dependency graph (i.e. a mapping from a task to
            # the tasks that depend on it)

            # This is kind-of a topological sort. However, we don't do the full
            # topological sort since we would then have to scan all tasks each
            # time for tasks that have no currently running prerequisites

            # The queue is the set of tasks for which all prerequisites have
            # been successfully executed (or where not needed). I.e. it is the
            # set of tasks that can be queued for execution.
            queue = roots.to_a
            processed = Set.new
            while true
                if queue.empty?
                    # If we have pending workers, wait for one to be finished
                    # until either they are all finished or the queue is not
                    # empty anymore
                    while queue.empty? && available_workers.size != workers.size
                        wait_for_worker_to_end(processed, queue)
                    end

                    if queue.empty? && available_workers.size == workers.size
                        break
                    end
                end

                pending_task = queue.pop
                #puts "#{processed.size} tasks processed so far, #{tasks.size} total"
                if pending_task.instance_variable_get(:@already_invoked) || !pending_task.needed?
                    process_finished_task(pending_task, processed, queue)
                    next
                end

                # Get a job server token
                job_server.get

                while !finished_workers.empty?
                    wait_for_worker_to_end(processed, queue)
                end

                # We do have a job server token, so we are allowed to allocate a
                # new worker if none are available
                if available_workers.empty?
                    w = Worker.new(job_server, finished_workers)
                    available_workers << w
                    workers << w
                end

                worker = available_workers.pop
                #puts "queueing #{pending_task}"
                worker.queue(pending_task)
            end

            if processed.size != tasks.size
                with_cycle = tasks.to_set
                (tasks.to_set - processed).each do |pending_task|
                    pending_task.prerequisite_tasks.each do |t|
                        if !processed.include?(t)
                            #puts "#{pending_task} => #{t}"
                        end
                    end
                end
                raise "cycle in task graph"
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


