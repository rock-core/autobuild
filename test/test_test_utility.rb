require 'autobuild/test'

module Autobuild
    describe TestUtility do
        before do
            @package = Package.new 'pkg'
            @utility = TestUtility.new('test', @package)
        end

        describe '#coverage_target_dir' do
            it 'defaults to the utility\'s target dir' do
                @utility.target_dir = '/some/path'
                assert_equal '/some/path/coverage', @utility.coverage_target_dir
            end

            it 'may be set explicitly' do
                @utility.target_dir = '/some/path'
                @utility.coverage_target_dir = '/some/other/path'
                assert_equal '/some/other/path', @utility.coverage_target_dir
            end

            it 'roots explicit target dir on the package prefix' do
                @package.prefix = '/package'
                @utility.target_dir = '/some/path'
                @utility.coverage_target_dir = 'some/other/path'
                assert_equal '/package/some/other/path', @utility.coverage_target_dir
            end
        end
    end
end

