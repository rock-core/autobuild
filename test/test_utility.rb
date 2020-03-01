require 'autobuild/test'

module Autobuild
    describe Utility do
        before do
            @package = Package.new 'pkg'
            @utility = Utility.new('test', @package)
        end

        describe '#available?' do
            it 'is false by default' do
                refute @utility.available?
            end

            it 'is false if only a block is defined' do
                @utility.task { }
                refute @utility.available?
            end

            it 'is false if only a source dir is defined' do
                @utility.source_dir = '/some/path'
                refute @utility.available?
            end

            it 'is false if only no_results is set' do
                @utility.no_results = true
                refute @utility.available?
            end

            it 'is true if a block has been defined and the source dir is set' do
                @utility.task { }
                @utility.source_dir = '/some/path'
                assert @utility.available?
            end

            it 'is true if a block has been defined and no_results is set' do
                @utility.task { }
                @utility.no_results = true
                assert @utility.available?
            end

            it 'may be forcefully set to false' do
                @utility.task { }
                @utility.source_dir = '/some/path'
                @utility.available = false
                refute @utility.available?
            end
        end

        describe "#enabled" do
            it 'is true by default even if available? is true' do
                flexmock(@utility).should_receive(available?: true)
                assert @utility.enabled?
            end

            it 'is always false if available? is false' do
                flexmock(@utility).should_receive(available?: false)
                @utility.enabled = true
                refute @utility.enabled?
            end

            it 'is may be forcefully set to false' do
                flexmock(@utility).should_receive(available?: true)
                @utility.enabled = false
                refute @utility.enabled?
            end
        end

        describe '#call_task_block' do
            before do
                @utility.source_dir = '/some/dir'
            end

            describe 'with a result directory' do
                it 'warns if the block did not create the output directory' do
                    flexmock(@package)
                    @package.should_receive(:warn).with("%s: failed to call test").once
                    @package.should_receive(:warn)
                            .with(%r{^%s: /some/dir was expected to be a directory}).once
                    @utility.call_task_block
                end

                it 'attempts an install if the block raised and install_on_error is set' do
                    flexmock(@utility, install_on_error?: true)
                    @utility.should_receive(:install).once
                    @utility.task { raise "something" }
                    @utility.call_task_block
                end

                it 'does not attempt a second install if the install step failed' do
                    flexmock(@utility, install_on_error?: true)
                    @utility.should_receive(:install).once.and_raise(RuntimeError)
                    @utility.call_task_block
                end
            end

            describe 'with no_results set' do
                it 'does not warn and does not attempt to install' do
                    @utility.no_results = true
                    flexmock(@package).should_receive(:warn).never
                    flexmock(@utility).should_receive(:install).never
                    @utility.call_task_block
                end
            end
        end
    end
end
