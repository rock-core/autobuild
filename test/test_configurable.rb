require 'autobuild/test'

module Autobuild
    describe Configurable do
        before do
            @klass = Class.new(Configurable) do
                attr_accessor :configurestamp
                attr_accessor :buildstamp
            end
            @package = flexmock(@klass.new)
            @package.srcdir = make_tmpdir
            @package.prefix = make_tmpdir
            @package.configurestamp = File.join(@package.prefix, 'configure-stamp')
            @package.buildstamp = File.join(@package.prefix, 'build-stamp')
        end

        it 'calls configure, build and install in this order' do
            @package.should_receive(:configure).once.globally.ordered
            @package.should_receive(:build).once.globally.ordered
            @package.should_receive(:install).once.globally.ordered
            prepare_and_build_package(@package)
        end

        it 'skips configure if the configurestamp is up-to-date' do
            FileUtils.touch @package.configurestamp
            @package.should_receive(:configure).never
            @package.should_receive(:build).once.globally.ordered
            @package.should_receive(:install).once.globally.ordered
            prepare_and_build_package(@package)
        end

        it 'skips configure and build if both buildstamp and configurestamp are up-to-date' do
            FileUtils.touch @package.configurestamp
            FileUtils.touch @package.buildstamp
            @package.should_receive(:configure).never
            @package.should_receive(:build).never
            @package.should_receive(:install).once
            prepare_and_build_package(@package)
        end

        it 'does build if configurestamp is outdated even if buildstamp is up-to-date' do
            FileUtils.touch @package.buildstamp
            @package.should_receive(:configure).once.globally.ordered
            @package.should_receive(:build).once.globally.ordered
            @package.should_receive(:install).once.globally.ordered
            prepare_and_build_package(@package)
        end

        it 'sets install_invoked? at configure time' do
            def @package.configure
                unless install_invoked?
                    raise Minitest::Failed, 'install_invoked? is not set'
                end
            end
            def @package.build
                unless install_invoked?
                    raise Minitest::Failed, 'install_invoked? is not set'
                end
            end
            prepare_and_build_package(@package)
        end

        it 'sets install_invoked? at build time' do
            FileUtils.touch @package.configurestamp
            def @package.build
                unless install_invoked?
                    raise Minitest::Failed, 'install_invoked? is not set'
                end
            end
            prepare_and_build_package(@package)
        end

        describe '#configure' do
            it 'creates the configurestamp if it does not exist yet' do
                t0 = Time.now
                sleep 0.01 # 1ms resolution for mtime
                @package.configure
                assert(t0 < File.stat(@package.configurestamp).mtime)
            end

            it 'updates the configurestamp' do
                FileUtils.touch @package.configurestamp
                t0 = Time.now
                sleep 0.01 # 1ms resolution for mtime
                @package.configure
                assert(t0 < File.stat(@package.configurestamp).mtime)
            end

            it 'accepts an existing builddir directory' do
                FileUtils.mkdir_p @package.builddir
                @package.configure
            end

            it 'creates the build directory' do
                @package.configure
                assert File.directory?(@package.builddir)
            end

            it 'fails if the builddir exists but is not a directory' do
                FileUtils.touch @package.builddir
                assert_raises(ConfigException) do
                    @package.configure
                end
            end
        end
    end
end
