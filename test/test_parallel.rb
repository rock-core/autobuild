require 'autobuild/test'

module Autobuild
    describe RakeTaskParallelism do
        describe '#invoke_parallel' do
            before do
                @tasks = (0...10).map { |i| Rake::Task.define_task(i.to_s) }

                @runner = RakeTaskParallelism.new

                @tasks[0].enhance([@tasks[1], @tasks[2]])
                @tasks[1].enhance([@tasks[3]])
                @tasks[2].enhance([@tasks[3]])

                @recorder = flexmock
            end

            it 'yields completed tasks in the main thread' do
                main_thread = Thread.current
                order = []
                callback = proc do |task|
                    assert_equal main_thread, Thread.current
                    order << task
                end

                @runner.invoke_parallel(@tasks[0, 4].shuffle,
                                        completion_callback: callback)

                assert_equal @tasks[3], order[0]
                assert_equal @tasks[1, 2].to_set, order[1, 2].to_set
                assert_equal @tasks[0], order[3]
            end

            it 'considers a task only once' do
                @recorder.should_receive(:called).with(0).once
                @recorder.should_receive(:called).with(3).once
                @tasks[0].enhance { @recorder.called(0) }
                @tasks[3].enhance { @recorder.called(3) }

                @runner.invoke_parallel(@tasks.shuffle)
            end

            it 'processes tasks in dependency order' do
                mutex = Mutex.new
                order = []
                4.times do |i|
                    @tasks[i].enhance { mutex.synchronize { order << i } }
                end

                @runner.invoke_parallel(@tasks.shuffle)

                assert_equal [1, 2].to_set, order[1, 2].to_set
                assert_equal 3, order.first
                assert_equal 0, order.last
            end

            describe 'disabled packages' do
                it 'does not invoke a disabled task' do
                    2.times do |i|
                        @tasks[i].disabled!
                        @tasks[i].enhance { @recorder.called }
                    end
                    @recorder.should_receive(:called).never

                    @runner.invoke_parallel(@tasks.shuffle)
                end

                it 'still considers the dependencies of a disabled task' do
                    2.times { |i| @tasks[i + 1].disabled! }
                    @tasks[0].enhance { @recorder.called }
                    @recorder.should_receive(:called).once

                    @runner.invoke_parallel(@tasks.shuffle)
                end
            end
        end
    end
end
