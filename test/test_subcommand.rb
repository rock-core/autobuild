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
end
