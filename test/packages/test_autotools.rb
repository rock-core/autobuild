require 'autobuild/test'

module Autobuild
    describe Autotools do
        attr_reader :root_dir, :package, :prefix

        before do
            @root_dir = make_tmpdir
            @package = Autobuild.autotools :package
            prefix = File.join(root_dir, 'prefix')
            build  = File.join(root_dir, 'build')
            log    = File.join(prefix, 'log')

            package.srcdir = File.join(root_dir, 'srcdir')
            FileUtils.mkdir_p package.srcdir
            package.prefix = prefix
            package.logdir = log
            package.builddir = build

            flexmock(@package)
        end

        def touch_in_builddir(*dirs, file)
            full_path = File.join(@package.builddir, *dirs, file)
            FileUtils.mkdir_p File.join(@package.builddir, *dirs)
            FileUtils.touch full_path
            full_path
        end

        def touch_in_srcdir(*dirs, file)
            full_path = File.join(@package.srcdir, *dirs, file)
            FileUtils.mkdir_p File.join(@package.srcdir, *dirs)
            FileUtils.touch full_path
            full_path
        end

        describe "#prepare" do
            it "forces reconfiguration on a fresh checkout" do
                FileUtils.rm_rf @package.srcdir
                importer = ArchiveImporter.new(
                    "file://" + File.join(__dir__, '..', 'data', 'autotools-fresh-checkout.tar'))
                @package.import = importer
                @package.import
                @package.prepare
                refute File.file?(File.join(@package.srcdir, 'configure'))
            end

            it "raises if autoconf is enabled but there is no configure.in/configure.ac" do
                @package.using[:autoconf] = true
                assert_raises(Autobuild::PackageException) do
                    @package.prepare
                end
            end

            describe "autodetection of which autotools stages are needed" do
                describe "autoconf and aclocal" do
                    it "enables both if there is a configure.in file" do
                        touch_in_srcdir 'configure.in'
                        @package.prepare
                        assert @package.using[:autoconf]
                        assert @package.using[:aclocal]
                    end
                    it "enables both if there is a configure.ac file" do
                        touch_in_srcdir 'configure.ac'
                        @package.prepare
                        assert @package.using[:autoconf]
                        assert @package.using[:aclocal]
                    end
                    it "enables only autoconf if aclocal is explicitly disabled" do
                        @package.using[:aclocal] = false
                        touch_in_srcdir 'configure.ac'
                        @package.prepare
                        assert @package.using[:autoconf]
                        refute @package.using[:aclocal]
                    end
                    it "leaves both disabled if there is neither configure.in nor configure.ac" do
                        @package.prepare
                        refute @package.using[:autoconf]
                        refute @package.using[:aclocal]
                    end
                    it "leaves autoconf and does not enable aclocal if it autoconf is explicitely disabled" do
                        @package.using[:autoconf] = false
                        touch_in_srcdir 'configure.ac'
                        @package.prepare
                        refute @package.using[:autoconf]
                        refute @package.using[:aclocal]
                    end
                    it "leaves autoconf and leaves an explicitly enabled aclocal if autoconf is explicitely disabled" do
                        @package.using[:autoconf] = false
                        @package.using[:aclocal] = true
                        touch_in_srcdir 'configure.ac'
                        @package.prepare
                        refute @package.using[:autoconf]
                        assert @package.using[:aclocal]
                    end
                end

                describe "automake" do
                    it "enables it if there is a Makefile.am" do
                        touch_in_srcdir 'Makefile.am'
                        @package.prepare
                        assert @package.using[:automake]
                    end
                    it "leaves it disabled if there is no Makefile.am" do
                        @package.prepare
                        refute @package.using[:automake]
                    end
                    it "leaves it disabled if there is a Makefile.am but it was explicitly disabled" do
                        @package.using[:automake] = false
                        touch_in_srcdir 'Makefile.am'
                        @package.prepare
                        refute @package.using[:automake]
                    end
                end

                describe "libtool" do
                    it "enables it if there is a ltmain.sh" do
                        touch_in_srcdir 'ltmain.sh'
                        @package.prepare
                        assert @package.using[:libtool]
                    end
                    it "leaves it disabled if there is no Makefile.am" do
                        @package.prepare
                        refute @package.using[:libtool]
                    end
                    it "leaves it disabled if there is a Makefile.am but it was explicitly disabled" do
                        @package.using[:libtool] = false
                        touch_in_srcdir 'ltmain.sh'
                        @package.prepare
                        refute @package.using[:libtool]
                    end
                end

                describe "autogen" do
                    it "enables it if there is an autogen script" do
                        touch_in_srcdir 'autogen'
                        @package.prepare
                        assert_equal 'autogen', @package.using[:autogen]
                    end
                    it "enables it if there is an autogen.sh script" do
                        touch_in_srcdir 'autogen.sh'
                        @package.prepare
                        assert_equal 'autogen.sh', @package.using[:autogen]
                    end
                    it "leaves it disabled if there is no autogen script" do
                        @package.prepare
                        refute @package.using[:autogen]
                    end
                    it "leaves it disabled if there is an autogen script but autogen is explicitly disabled" do
                        @package.using[:autogen] = false
                        touch_in_srcdir 'autogen'
                        @package.prepare
                        refute @package.using[:autogen]
                    end
                end
            end

            describe "autodetection of changed flags" do
                before do
                    FileUtils.mkdir_p @package.builddir
                    File.open(@package.configurestamp, 'w', 0700) do |io|
                        io.puts "#! /bin/sh"
                        io.puts "echo garbage"
                        io.puts "echo \"blablabla with options \\\"--test --options --prefix=#{@package.prefix}\\\"\""
                        io.puts "echo garbage"
                    end
                    File.open(File.join(@package.builddir, 'configure'), 'w', 0700).close
                end

                it "reconfigures if flags have been removed" do
                    @package.prepare
                    refute File.exist?(@package.configurestamp)
                end

                it "reconfigures if new flags have been added" do
                    @package.configureflags << "--test" << "--options" << "--new-flag"
                    @package.prepare
                    refute File.exist?(@package.configurestamp)
                end

                it "reconfigures on envvar change if the envvar is part of configureflags" do
                    File.open(@package.configurestamp, 'w', 0700) do |io|
                        io.puts "#! /bin/sh"
                        io.puts "echo garbage"
                        io.puts "echo \"blablabla with options \\\"ENV=VAR --prefix=#{@package.prefix}\\\"\""
                        io.puts "echo garbage"
                    end
                    @package.configureflags << "ENV=NEWVAL"
                    @package.prepare
                    refute File.exist?(@package.configurestamp)
                end

                it "does not reconfigure on envvar change if the envvar is not part of configureflags" do
                    File.open(@package.configurestamp, 'w', 0700) do |io|
                        io.puts "#! /bin/sh"
                        io.puts "echo garbage"
                        io.puts "echo \"blablabla with options \\\"ENV=VAR --prefix=#{@package.prefix}\\\"\""
                        io.puts "echo garbage"
                    end
                    @package.prepare
                    assert File.exist?(@package.configurestamp)
                end

                it "avoids reconfiguration if config.status reports the same flags than the expected flags" do
                    @package.configureflags << "--test" << "--options"
                    @package.prepare
                    assert File.exist?(@package.configurestamp)
                end

                it "raises if no lines from config.status match the expected pattern" do
                    FileUtils.mkdir_p @package.builddir
                    File.open(@package.configurestamp, 'w', 0700) do |io|
                        io.puts "#! /bin/sh"
                        io.puts "echo garbage"
                        io.puts "echo garbage"
                    end
                    File.open(File.join(@package.builddir, 'configure'), 'w', 0700).close
                    assert_raises(Autotools::UnexpectedConfigStatusOutput) { @package.prepare }
                end
            end

            describe "the regen stage" do
                before do
                    touch_in_srcdir 'configure.in'
                end

                it "runs libtoolize and autogen if they are enabled" do
                    @package.using[:libtool] = true
                    @package.using[:autogen] = '/my/autogen/script'
                    @package.should_receive(:run).with(any, /libtoolize/, '--copy',
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, "/my/autogen/script",
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /configure/, any, any).
                        once.globally.ordered
                    conffile = @package.prepare
                    Rake::Task[conffile].invoke
                end

                it "ignores the other stages if there is an autogen" do
                    @package.using[:libtool] = true
                    @package.using[:autogen] = '/my/autogen/script'
                    @package.using[:aclocal] = true
                    @package.using[:autoconf] = true
                    @package.using[:automake] = true
                    @package.should_receive(:run).with(any, /libtoolize/, '--copy',
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, "/my/autogen/script",
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /configure/, any, any).
                        once.globally.ordered
                    conffile = @package.prepare
                    Rake::Task[conffile].invoke
                end

                it "runs libtool, aclocal, autoheader, autoconf and automake in this order" do
                    @package.using[:libtool] = true
                    @package.using[:aclocal] = true
                    @package.using[:autoheader] = true
                    @package.using[:autoconf] = true
                    @package.using[:automake] = true
                    @package.should_receive(:run).with(any, /libtoolize/, '--copy',
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /aclocal/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /autoconf/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /autoheader/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /automake/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /configure/, any, any).
                        once.globally.ordered
                    conffile = @package.prepare
                    Rake::Task[conffile].invoke
                end

                it "passes the respective tool's flags" do
                    @package.using[:libtool] = true
                    @package.aclocal_flags << "--test-aclocal"
                    @package.using[:aclocal] = true
                    @package.autoheader_flags << "--test-autoheader"
                    @package.using[:autoheader] = true
                    @package.autoconf_flags << "--test-autoconf"
                    @package.using[:autoconf] = true
                    @package.automake_flags << "--test-automake"
                    @package.using[:automake] = true
                    @package.should_receive(:run).with(any, /libtoolize/, '--copy',
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /aclocal/, '--test-aclocal',
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /autoconf/, '--test-autoconf',
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /autoheader/, '--test-autoheader',
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /automake/, '--test-automake',
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with_any_args.
                        once.globally.ordered
                    conffile = @package.prepare
                    Rake::Task[conffile].invoke
                end

                it "ignores libtool if it is disabled" do
                    @package.using[:libtool] = false
                    @package.using[:aclocal] = true
                    @package.using[:autoheader] = true
                    @package.using[:autoconf] = true
                    @package.using[:automake] = true
                    @package.should_receive(:run).with(any, "aclocal",
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /autoconf/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /autoheader/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /automake/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /configure/, any, any).
                        once.globally.ordered
                    conffile = @package.prepare
                    Rake::Task[conffile].invoke
                end

                it "ignores aclocal if it is disabled" do
                    @package.using[:libtool] = true
                    @package.using[:aclocal] = false
                    @package.using[:autoheader] = true
                    @package.using[:autoconf] = true
                    @package.using[:automake] = true
                    @package.should_receive(:run).with(any, /libtoolize/, '--copy',
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /autoconf/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /autoheader/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /automake/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /configure/, any, any).
                        once.globally.ordered
                    conffile = @package.prepare
                    Rake::Task[conffile].invoke
                end

                it "ignores autoconf if it is disabled" do
                    @package.using[:libtool] = true
                    @package.using[:aclocal] = true
                    @package.using[:autoconf] = false
                    @package.using[:autoheader] = true
                    @package.using[:automake] = true
                    @package.should_receive(:run).with(any, /libtoolize/, '--copy',
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /aclocal/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /autoheader/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /automake/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /configure/, any, any).
                        once.globally.ordered
                    conffile = @package.prepare
                    Rake::Task[conffile].invoke
                end

                it "ignores autoheader if it is disabled" do
                    @package.using[:libtool] = true
                    @package.using[:aclocal] = true
                    @package.using[:autoconf] = true
                    @package.using[:autoheader] = false
                    @package.using[:automake] = true
                    @package.should_receive(:run).with(any, /libtoolize/, '--copy',
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /aclocal/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /autoconf/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /automake/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /configure/, any, any).
                        once.globally.ordered
                    conffile = @package.prepare
                    Rake::Task[conffile].invoke
                end

                it "ignores automake if it is disabled" do
                    @package.using[:libtool] = true
                    @package.using[:aclocal] = true
                    @package.using[:autoconf] = true
                    @package.using[:autoheader] = true
                    @package.using[:automake] = false
                    @package.should_receive(:run).with(any, /libtoolize/, '--copy',
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /aclocal/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /autoconf/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /autoheader/,
                        working_directory: @package.srcdir).once.globally.ordered
                    @package.should_receive(:run).with(any, /configure/, any, any).
                        once.globally.ordered
                    conffile = @package.prepare
                    Rake::Task[conffile].invoke
                end
            end
        end

        describe "#prepare_for_forced_build" do
            it "deletes the configure stamp to force reconfiguration" do
                conf_status = touch_in_builddir('config.status')
                @package.prepare_for_forced_build
                refute File.exist?(conf_status)
            end
            it "keeps the configure script if autoconf is disabled" do
                @package.using[:autoconf] = false
                conf = touch_in_srcdir('configure')
                @package.prepare_for_forced_build
                assert File.exist?(conf)
            end
            it "deletes the configure script if autoconf is enabled" do
                @package.using[:autoconf] = true
                conf = touch_in_srcdir('configure')
                @package.prepare_for_forced_build
                refute File.exist?(conf)
            end
            it "keeps all Makefile.in files if automake is disabled" do
                @package.using[:automake] = false
                root = touch_in_srcdir 'Makefile.in'
                src  = touch_in_srcdir 'src', 'Makefile.in'
                @package.prepare_for_forced_build
                assert File.exist?(root)
                assert File.exist?(src)
            end
            it "deletes all Makefile.in files if automake is enabled" do
                @package.using[:automake] = true
                root = touch_in_srcdir 'Makefile.in'
                src  = touch_in_srcdir 'src', 'Makefile.in'
                @package.prepare_for_forced_build
                refute File.exist?(root)
                refute File.exist?(src)
            end
        end

        describe "#use" do
            it "handles a hash that enables subsystems" do
                @package.use autotools: true
                assert_equal true, @package.using[:autotools]
            end

            it "handles a hash that disables subsystems" do
                @package.use autotools: true
                @package.use autotools: false
                assert_equal false, @package.using[:autotools]
            end

            it "handles a hash that restores a subsystem's autodetection" do
                @package.use autotools: true
                @package.use autotools: nil
                assert_nil @package.using[:autotools]
            end

            it "handles a hash that provides explicit command names" do
                @package.use autotools: '/path/to/autotools'
                assert_equal '/path/to/autotools', @package.using[:autotools]
            end
        end

        describe '#build' do
            it 'runs build command' do
                @package.use bear: false
                @package.should_receive(:run).with(any, Autobuild.tool(:make),
                    "-j#{@package.parallel_build_level}").once
                @package.send(:build)
            end

            it 'runs build command using bear' do
                @package.use bear: '/path/to/bear'
                @package.should_receive(:run).with(any, '/path/to/bear', '-a',
                    Autobuild.tool(:make), "-j#{@package.parallel_build_level}").once
                @package.send(:build)
            end
        end

        describe '#tool_program' do
            it 'allows string argument' do
                package.use bear: '/path/to/bear'
                assert_equal '/path/to/bear', package.tool_program('bear')
            end

            it 'allows symbol argument' do
                package.use bear: '/the/path/bear'
                assert_equal '/the/path/bear', package.tool_program(:bear)
            end

            it 'returns the default program' do
                Autobuild.programs['bear'] = '/foo/bear'
                package.use bear: nil
                assert_equal '/foo/bear', package.tool_program(:bear)

                package.use bear: false
                assert_equal '/foo/bear', package.tool_program(:bear)

                package.use bear: true
                assert_equal '/foo/bear', package.tool_program(:bear)
            end
        end

        describe 'bear tool support' do
            describe '#enable_bear_globally' do
                it 'enables bear tool globally' do
                    Autotools.enable_bear_globally = true
                    assert_equal true, package.using_bear?
                    assert_equal true, Autotools.enable_bear_globally?
                end

                it 'disables bear tool globally' do
                    Autotools.enable_bear_globally = false
                    assert_equal false, package.using_bear?
                    assert_equal false, Autotools.enable_bear_globally?
                end
            end

            describe '#using_bear?' do
                it 'honors package setting over global setting' do
                    Autotools.enable_bear_globally = false
                    package.use bear: true
                    assert_equal true, package.using_bear?
                    assert_equal false, Autotools.enable_bear_globally?

                    Autotools.enable_bear_globally = true
                    package.use bear: false
                    assert_equal false, package.using_bear?
                    assert_equal true, Autotools.enable_bear_globally?
                end
            end
        end
    end
end

