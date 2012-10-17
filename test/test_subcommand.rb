$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__))
require 'test/unit'
require 'tools'

require 'autobuild'
require 'tmpdir'
require 'fileutils'
require 'flexmock/test_unit'

class TC_Subcommand < Test::Unit::TestCase
EXAMPLE_1 = <<EOF
This is a file
It will be the first part of the two-part cat
EOF

EXAMPLE_2 = <<EOF
This is another file
It will be the second part of the two-part cat
EOF

    attr_reader :tmpdir
    attr_reader :source1, :source2
    def setup
        @tmpdir = Autobuild.logdir = TestTools.tempdir

        # Write example files
        @source1 = File.join(tmpdir, 'source1')
        @source2 = File.join(tmpdir, 'source2')
        File.open(source1, 'w+') { |f| f.write(EXAMPLE_1) }
        File.open(source2, 'w+') { |f| f.write(EXAMPLE_2) }

        super
    end

    def teardown
        super
        TestTools.clean
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

