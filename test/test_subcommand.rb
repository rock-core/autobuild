require 'autobuild/test'

class TestSubcommand < Minitest::Test
    EXAMPLE_1 = <<-EXAMPLE_END.freeze
This is a file
It will be the first part of the two-part cat
    EXAMPLE_END

    EXAMPLE_2 = <<-EXAMPLE_END.freeze
This is another file
It will be the second part of the two-part cat
    EXAMPLE_END

    attr_reader :source1, :source2

    def setup
        super

        Autobuild.logdir = tempdir

        # Write example files
        @source1 = File.join(tempdir, 'source1')
        @source2 = File.join(tempdir, 'source2')
        File.open(source1, 'w+') { |f| f.write(EXAMPLE_1) }
        File.open(source2, 'w+') { |f| f.write(EXAMPLE_2) }
    end

    def test_behaviour_on_unexpected_error
        flexmock(Autobuild::Subprocess).should_receive(:exec).and_raise(::Exception)
        assert_raises(Autobuild::SubcommandFailed) { Autobuild::Subprocess.run('test', 'test', 'does_not_exist') }
    end

    def test_behaviour_on_inexistent_command
        assert_raises(Autobuild::SubcommandFailed) { Autobuild::Subprocess.run('test', 'test', 'does_not_exist') }
    end

    def test_behaviour_on_interrupt
        flexmock(Autobuild::Subprocess).should_receive(:exec).and_raise(Interrupt)
        assert_raises(Interrupt) { Autobuild::Subprocess.run('test', 'test', 'does_not_exist') }
    end

    def test_it_works_around_a_broken_waitpid
        Autobuild::Subprocess.workaround_broken_waitpid = true
        pid = fork { }
        result = Process.waitpid2(pid)

        flexmock(Process)
            .should_receive(:waitpid2)
            .and_return(nil, result)

        Autobuild::Subprocess.waitpid2(pid)
    ensure
        Autobuild::Subprocess.workaround_broken_waitpid = false
    end

    def test_it_displays_the_waitpid_brokenness_after_one_second
        Autobuild::Subprocess.workaround_broken_waitpid = true
        pid = fork { }
        result = Process.waitpid2(pid)

        queue = [nil, result]
        flexmock(Process)
            .should_receive(:waitpid2)
            .and_return { sleep 1.1; queue.shift }

        out, err = capture_io do
            Autobuild::Subprocess.waitpid2(pid)
        end
        assert_equal "Received result of #{pid}\n", err
        assert queue.empty?
    ensure
        Autobuild::Subprocess.workaround_broken_waitpid = false
    end

    def test_it_handles_the_subprocess_disappearing_during_waitpid_polling
        Autobuild::Subprocess.workaround_broken_waitpid = true
        pid = fork { }
        result = Process.waitpid2(pid)

        queue = [nil, result]
        flexmock(Process)
            .should_receive(:waitpid2)
            .and_raise(Errno::ECHILD)

        out, err = capture_io do
            Autobuild::Subprocess.waitpid2(pid)
        end
        assert_equal "process #{pid} disappeared without letting us reap it\n", err
    ensure
        Autobuild::Subprocess.workaround_broken_waitpid = false
    end
end
