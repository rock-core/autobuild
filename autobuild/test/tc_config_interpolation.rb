require 'test/unit'
require 'autobuild/config-interpolator'

require 'yaml'
require 'stringio'

class TC_ConfigInterpolation < Test::Unit::TestCase
WELL_FORMED = <<EOF
defines:
    global_prefix: /home/doudou
    srcdir: ${global_prefix}/src
    prefix: ${global_prefix}/build
    nice: 10

autobuild:
    srcdir: $srcdir
    prefix: $prefix
    nice: $nice

EOF
        
    def setup
        @wellformed = StringIO.open(WELL_FORMED, 'r') { |d| YAML.load(d) }
    end

    def teardown
        @wellformed = nil
    end

    # Check that interpolation matches both forms ${var} and $var
    def test_match
        data = @wellformed['defines']['srcdir']
        all_matches = []
        Interpolator::PartialMatch.each_match(data) { |m| all_matches << m[1] }
        assert_equal( ['global_prefix'], all_matches )
        
        data = @wellformed['autobuild']['srcdir']
        all_matches = []
        Interpolator::PartialMatch.each_match(data) { |m| all_matches << m[2] }
        assert_equal( ['srcdir'], all_matches )
    end
        
    def test_interpolation
        data = Interpolator.interpolate(@wellformed)
        assert_equal('/home/doudou/src', data["autobuild"]["srcdir"])
        assert_equal('/home/doudou/build', data["autobuild"]["prefix"])
        assert_equal(10, data["autobuild"]["nice"])
        assert_kind_of(Fixnum, data["autobuild"]["nice"])
    end
end

