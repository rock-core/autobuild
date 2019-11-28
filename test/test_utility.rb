require 'autobuild/test'

module Autobuild
    describe Utility do
        before do
            @package = Package.new 'pkg'
            @utility = Utility.new('test', @package)
        end

        describe '#call_task_block' do
            before do
                @utility.source_dir = '/some/dir'
            end

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
    end
end
