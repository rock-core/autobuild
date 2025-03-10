require 'autobuild/test'

module Autobuild
    describe Subprocess do
        before do
            @example1 = <<~EXAMPLE_END.freeze
                This is a file
                It will be the first part of the two-part cat
            EXAMPLE_END

            @example2 = <<~EXAMPLE_END.freeze
                This is a file
                It will be the second part of the two-part cat
            EXAMPLE_END

            Autobuild.logdir = tempdir

            # Write example files
            @source1 = File.join(tempdir, 'source1')
            @source2 = File.join(tempdir, 'source2')
            File.open(@source1, 'w+') { |f| f.write(@example1) }
            File.open(@source2, 'w+') { |f| f.write(@example2) }
        end

        after do
            Autobuild.keep_oldlogs = true
            Autobuild::Subprocess.transparent_mode = false
        end

        describe "basic execution behavior" do
            it "executes a subcommand and returns the command output" do
                result = Subprocess.run("test", "phase", "cat", @source1)
                assert_equal @example1.chomp.split("\n"), result
            end

            it "raises SubcommandFailed if the command failed" do
                e = assert_raises(SubcommandFailed) do
                    Subprocess.run(
                        "test", "phase", "cat", "/does/not/exist",
                        env: { "LANG" => "C" }
                    )
                end

                assert_equal "cat /does/not/exist", e.command
                assert_equal 1, e.status
                assert_match(/No such file or directory/, e.output.first)
            end

            it "sets the SubcommandFailed retry flag to false by default" do
                e = assert_raises(SubcommandFailed) do
                    Subprocess.run("test", "phase", "cat", "/does/not/exist")
                end
                refute e.retry?
            end

            it "sets the SubcommandFailed retry flag to true "\
               "if the retry argument is true" do
                e = assert_raises(SubcommandFailed) do
                    Subprocess.run("test", "phase", "cat", "/does/not/exist", retry: true)
                end
                assert e.retry?
            end

            it "does not retry errors to spawn the command" do
                e = assert_raises(SubcommandFailed) do
                    Subprocess.run("test", "phase", "/does/not/exist", retry: true)
                end
                refute e.retry?
            end

            it "passes the given environment" do
                result = Subprocess.run(
                    "test", "phase", "sh", "-c", "echo $FOO", env: { "FOO" => "TEST" }
                )
                assert_equal ["TEST"], result
            end

            it "executes the command in the provided working directory, if given" do
                dir = make_tmpdir
                result = Subprocess.run(
                    "test", "phase", "pwd",
                    working_directory: dir
                )
                assert_equal [dir], result
            end

            it "yields the command output if a block is given" do
                lines = []
                result = Subprocess.run("test", "phase", "cat", @source1) do |line|
                    lines << line
                end
                assert_equal @example1.chomp.split("\n"), lines
                assert_equal @example1.chomp.split("\n"), result
            end

            it "passes the command output through if transparent mode is set" do
                Autobuild::Subprocess.transparent_mode = true
                stdout = []
                block = []
                flexmock(STDOUT).should_receive(:puts).and_return { |line| stdout << line }
                result = Subprocess.run("test", "phase", "cat", @source1) do |line|
                    block << line
                end

                expected_lines = @example1.chomp.split("\n")
                assert_equal expected_lines, result
                with_prefix = expected_lines.map { |l| "test:phase: #{l}" }
                assert_equal with_prefix, stdout
                assert_equal [], block
            end

            it "reports that a command was terminated by a signal "\
               "from within the error message" do
                e = assert_raises(SubcommandFailed) do
                    Subprocess.run("test", "phase", "sh", "-c", "kill -KILL $$")
                end
                assert_equal "'sh -c kill -KILL $$' terminated by signal 9",
                             e.message.split("\n")[-2].strip
            end

            it "raises Interrupt if the command was killed with SIGINT" do
                assert_raises(Interrupt) do
                    Subprocess.run("test", "phase", "sh", "-c", "kill -INT $$")
                end
            end
        end

        describe "input handling" do
            it "passes data from the file in 'input' to the subprocess" do
                result = Autobuild::Subprocess.run(
                    "test", "phase", "cat", input: @source1
                )
                assert_equal @example1.chomp.split("\n"), result
            end

            it "passes I/O input from input_streams to the subprocess" do
                result = File.open(@source1) do |source1_io|
                    File.open(@source2) do |source2_io|
                        Autobuild::Subprocess.run(
                            "test", "phase", "cat",
                            input_streams: [source1_io, source2_io]
                        )
                    end
                end

                expected =
                    @example1.chomp.split("\n") +
                    @example2.chomp.split("\n")
                assert_equal expected, result
            end
        end

        describe "log file management" do
            it "saves the subcommand output to a log file" do
                Subprocess.run("test", "phase", "cat", @source1)
                actual = File.read(File.join(Autobuild.logdir, "test-phase.log"))
                actual_lines = actual.split("\n")

                expected_lines = @example1.chomp.split("\n")
                assert_match Regexp.new(Regexp.quote("cat #{@source1}")), actual
                assert_equal expected_lines, actual_lines[-(expected_lines.size + 1)..-2]
            end

            it "handles package names with slashes" do
                Subprocess.run("dir/test", "phase", "cat", @source1)
                actual = File.read(File.join(Autobuild.logdir, "dir", "test-phase.log"))
                actual_lines = actual.split("\n")

                expected_lines = @example1.chomp.split("\n")
                assert_match Regexp.new(Regexp.quote("cat #{@source1}")), actual
                assert_equal expected_lines, actual_lines[-(expected_lines.size + 1)..-2]
            end

            it "appends to an old logfile if Autobuild.keep_oldlogs is set" do
                Autobuild.keep_oldlogs = true
                File.write(File.join(Autobuild.logdir, "test-phase.log"), "old content")
                Subprocess.run("test", "phase", "cat", @source1)

                actual = File.read(File.join(Autobuild.logdir, "test-phase.log"))
                assert_equal "old content\n", actual.each_line.first
                assert_match Regexp.new(Regexp.quote("cat #{@source1}")), actual
            end

            it "overwrites an old logfile if Autobuild.keep_oldlogs is unset" do
                Autobuild.keep_oldlogs = false
                File.write(File.join(Autobuild.logdir, "test-phase.log"), "old content")
                Subprocess.run("test", "phase", "cat", @source1)

                actual = File.read(File.join(Autobuild.logdir, "test-phase.log"))
                refute_equal "old content\n", actual.each_line.first
                assert_match Regexp.new(Regexp.quote("cat #{@source1}")), actual
            end

            it "always keeps a logfile that was produced in the same run" do
                Autobuild.keep_oldlogs = false
                Subprocess.run("test", "phase", "cat", @source1)
                Subprocess.run("test", "phase", "cat", @source2)
                actual = File.read(File.join(Autobuild.logdir, "test-phase.log"))
                assert_match Regexp.new(Regexp.quote("cat #{@source1}")), actual
                assert_match Regexp.new(Regexp.quote("cat #{@source2}")), actual
            end
        end
    end
end
