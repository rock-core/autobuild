require 'test/unit'
require 'fileutils'
require 'autobuild/options'
require 'autobuild/config'
require 'tmpdir'

require 'test/conffile-generator'

TESTDIR = File.join(File.dirname(__FILE__), 'dummy.yml')

class TC_Subcommand < Test::Unit::TestCase
EXAMPLE_1 = <<EOF
THis is a file
It will be the first part of the two-part cat
EOF

EXAMPLE_2 = <<EOF
This is another file
It will be the second part of the two-part cat
EOF

    attr_reader :tmpdir
    attr_reader :source1, :source2
    def setup
        # Configure with logdir=/tmp/<temp dir>
        @tmpdir = Dir::tmpdir + "/autobuild-#{Process.uid}"
        FileUtils.mkdir_p(tmpdir, :mode => 0700)

        conffile = ConffileGenerator.dummy(tmpdir)

        options = Options.default
        options.logdir = tmpdir
        File.open(conffile) do |confstream|
            Config.load confstream, options
        end

        # Write example files
        @source1 = File.join(tmpdir, 'source1')
        @source2 = File.join(tmpdir, 'source2')
        File.open(source1, 'w+') { |f| f.write(EXAMPLE_1) }
        File.open(source2, 'w+') { |f| f.write(EXAMPLE_2) }
    end

    def teardown
        FileUtils.rm_rf(tmpdir)
    end

    def test_subcommand
        assert_raise(SubcommandFailed) { || subcommand('test', 'copy', 'cat', 'bla') }
        
        subcommand('test', 'simple', 'cat', nil, '', source1)
        assert( FileUtils.identical?(source1, File.join(tmpdir, 'test-simple.log')) )

        subcommand('test', 'use-lt', 'cat', "<#{source1}")
        assert( FileUtils.identical?(source1, File.join(tmpdir, 'test-use-lt.log')) )

        subcommand('test', 'use-both', 'cat', source1, '-', "<#{source2}")
        result = File.open( File.join(tmpdir, 'test-use-both.log') ) do |f|
            f.readlines
        end
        assert_equal(EXAMPLE_1 + EXAMPLE_2, result.join(""))
    end
end

