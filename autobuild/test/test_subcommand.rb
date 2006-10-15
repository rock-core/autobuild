$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__))
require 'test/unit'
require 'tools'

require 'autobuild/config'
require 'autobuild/subcommand'
require 'tmpdir'
require 'fileutils'

include Autobuild

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
    end

    def teardown
        TestTools.clean
    end

    def test_logfiles
        assert_raise(SubcommandFailed) { || Subprocess.run('test', 'copy', 'cat', 'bla') }
        
        Subprocess.run('test', 'simple', 'cat', nil, '', source1)
	result_content = File.readlines(File.join(tmpdir, 'test-simple.log'))[1..-1].join
        assert_equal(EXAMPLE_1, result_content)

        Subprocess.run('test', 'use-lt', 'cat', "<#{source1}")
	result_content = File.readlines(File.join(tmpdir, 'test-use-lt.log'))[1..-1].join
        assert_equal(EXAMPLE_1, result_content)

        Subprocess.run('test', 'use-both', 'cat', source1, '-', "<#{source2}")
        result = File.open( File.join(tmpdir, 'test-use-both.log') ) do |f|
            f.readlines
        end
	result = result[1..-1].join
        assert_equal(EXAMPLE_1 + EXAMPLE_2, result)
    end
end

