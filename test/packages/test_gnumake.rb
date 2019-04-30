require 'autobuild/test'

module Autobuild
    describe "gnumake job server support" do
        before do
            @recorder = flexmock
            @pkg = flexmock
            @pkg.should_receive(parallel_build_level: 2).by_default
            flexmock(Autobuild)
            Autobuild.should_receive(parallel_build_level: @pkg.parallel_build_level)
                        .by_default
        end

        describe "GNU make detection" do
            it "returns true if the version string starts with GNU Make and has a version string" do
                @pkg.should_receive(:run).with('prepare', 'toolpath', '--version')
                    .and_return(["GNU Make 3.1.5"])
                assert Autobuild.make_is_gnumake?(@pkg, 'toolpath')
            end
            it "returns false if the version string starts with GNU Make but does not have a version string" do
                @pkg.should_receive(:run).with('prepare', 'toolpath', '--version')
                    .and_return(["GNU Make"])
                refute Autobuild.make_is_gnumake?(@pkg, 'toolpath')
            end
            it "returns false if the version string has GNU Make but not at the start" do
                @pkg.should_receive(:run).with('prepare', 'toolpath', '--version')
                    .and_return(["Some Other Make than GNU Make"])
                refute Autobuild.make_is_gnumake?(@pkg, 'toolpath')
            end
            it "returns false if the version string does include GNU Make" do
                @pkg.should_receive(:run).with('prepare', 'toolpath', '--version')
                    .and_return(["Some Make"])
                refute Autobuild.make_is_gnumake?(@pkg, 'toolpath')
            end
        end

        describe "GNU make version detection" do
            it "expects the version to be in the first line" do
                @pkg.should_receive(:run).with('prepare', 'toolpath', '--version')
                    .and_return(["GNU Make 3.5.1"])
                assert_equal Gem::Version.new("3.5.1"),
                             Autobuild.gnumake_version(@pkg, 'toolpath')
            end
            it "raises NotGNUMake if make is not GNU make" do
                @pkg.should_receive(:run).with('prepare', 'toolpath', '--version')
                    .and_return(["Some Other Make than GNU Make"])
                assert_raises(NotGNUMake) do
                    Autobuild.gnumake_version(@pkg, 'toolpath')
                end
            end
            it "raises NotGNUMake if make is GNU make but does not have the expected "\
               "version string" do
                @pkg.should_receive(:run).with('prepare', 'toolpath', '--version')
                    .and_return(["GNU Make"])
                assert_raises(NotGNUMake) do
                    Autobuild.gnumake_version(@pkg, 'toolpath')
                end
            end
        end

        describe "make_has_j_option" do
            it "returns true if make is GNU make" do
                Autobuild.should_receive(:make_is_gnumake?)
                    .with(@pkg, 'toolpath').and_return(true)
                assert Autobuild.make_has_j_option?(@pkg, 'toolpath')
            end
            it "returns false if make is not GNU make" do
                Autobuild.should_receive(:make_is_gnumake?)
                    .with(@pkg, 'toolpath').and_return(false)
                refute Autobuild.make_has_j_option?(@pkg, 'toolpath')
            end
        end

        describe "make_has_gnumake_jobserver" do
            it "returns true if make is GNU make" do
                Autobuild.should_receive(:make_is_gnumake?)
                    .with(@pkg, 'toolpath').and_return(true)
                assert Autobuild.make_has_gnumake_jobserver?(@pkg, 'toolpath')
            end
            it "returns false if make is not GNU make" do
                Autobuild.should_receive(:make_is_gnumake?)
                    .with(@pkg, 'toolpath').and_return(false)
                refute Autobuild.make_has_gnumake_jobserver?(@pkg, 'toolpath')
            end
        end

        describe "gnumake_jobserver_option" do
            before do
                @job_server = flexmock(
                    rio: flexmock(fileno: 42),
                    wio: flexmock(fileno: 21)
                )
            end

            it "returns --jobserver-auth for GNU make after 4.2.0" do
                flexmock(Autobuild).should_receive(:gnumake_version)
                    .with(@pkg, 'toolpath')
                    .and_return(Gem::Version.new("4.2.0"))
                options = Autobuild.gnumake_jobserver_option(
                    @job_server, @pkg, 'toolpath'
                )
                assert_equal ["--jobserver-auth=42,21", "-j"], options
            end

            it "returns --jobserver-fds for GNU make before 4.2.0" do
                flexmock(Autobuild).should_receive(:gnumake_version)
                    .with(@pkg, 'toolpath')
                    .and_return(Gem::Version.new("4.1.0"))
                options = Autobuild.gnumake_jobserver_option(
                    @job_server, @pkg, 'toolpath'
                )
                assert_equal ["--jobserver-fds=42,21", "-j"], options
            end
        end

        describe "invoke_make_parallel" do
            before do
                flexmock(Autobuild) # to clean the tests up a bit
                @job_server = flexmock
                Autobuild.should_receive(:parallel_task_manager)
                    .and_return(flexmock(job_server: @job_server))
                    .by_default
            end

            it "yields no options if make has no -j option at all" do
                Autobuild.should_receive(:make_has_j_option?).and_return(false)
                @recorder.should_receive(:record).with([]).once
                Autobuild.invoke_make_parallel(@pkg, 'toolpath') do |*args|
                    @recorder.record(args)
                end
            end

            it "yields a static -j option if there is no parallel build manager" do
                Autobuild.should_receive(parallel_task_manager: nil)
                Autobuild.should_receive(:make_has_j_option?).and_return(true)
                Autobuild.should_receive(:make_has_gnumake_jobserver?).and_return(false)
                @recorder.should_receive(:record).with(["-j2"]).once
                Autobuild.invoke_make_parallel(@pkg, 'toolpath') do |*args|
                    @recorder.record(args)
                end
            end

            it "allocates the tokens statically if make has no job server support" do
                Autobuild.should_receive(:make_has_j_option?).and_return(true)
                Autobuild.should_receive(:make_has_gnumake_jobserver?).and_return(false)
                @job_server.should_receive(:get).with(1).once.globally.ordered
                @recorder.should_receive(:record).with(["-j2"]).once.globally.ordered
                @job_server.should_receive(:put).with(1).once.globally.ordered
                Autobuild.invoke_make_parallel(@pkg, 'toolpath') do |*args|
                    @recorder.record(args)
                end
            end

            it "yields a static -j option if the package has a specific parallel build level" do
                Autobuild.should_receive(:make_has_j_option?).and_return(true)
                Autobuild.should_receive(:make_has_gnumake_jobserver?).and_return(true)
                Autobuild.should_receive(parallel_build_level: 4)
                @job_server.should_receive(:get).with(1).once.globally.ordered
                @recorder.should_receive(:record).with(["-j2"]).once.globally.ordered
                @job_server.should_receive(:put).with(1).once.globally.ordered
                Autobuild.invoke_make_parallel(@pkg, 'toolpath') do |*args|
                    @recorder.record(args)
                end
            end

            it "yields the job server options if supported" do
                Autobuild.should_receive(:make_has_j_option?).and_return(true)
                Autobuild.should_receive(:make_has_gnumake_jobserver?).and_return(true)
                Autobuild.should_receive(:gnumake_version).and_return(Gem::Version.new("4.2.1"))
                @job_server.should_receive(rio: flexmock(fileno: 42))
                @job_server.should_receive(wio: flexmock(fileno: 21))

                @recorder.should_receive(:record).with(["--jobserver-auth=42,21", "-j"])
                         .once.globally.ordered
                Autobuild.invoke_make_parallel(@pkg, 'toolpath') do |*args|
                    @recorder.record(args)
                end
            end
        end
    end
end
