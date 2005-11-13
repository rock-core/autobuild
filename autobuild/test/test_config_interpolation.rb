$LOAD_PATH.unshift File.expand_path('..', File.dirname(__FILE__))
$LOAD_PATH << File.expand_path('../lib', File.dirname(__FILE__))

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
    envvar: $ENVVAR

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
        data.gsub(Interpolator::PartialMatch) { |m| all_matches << ($1 || $2) }
        assert_equal( ['global_prefix'], all_matches )
        
        data = @wellformed['autobuild']['srcdir']
        all_matches = []
        data.gsub(Interpolator::PartialMatch) { |m| all_matches << ($1 || $2) }
        assert_equal( ['srcdir'], all_matches )
    end
        
    def test_interpolation
        ENV['ENVVAR'] = 'envvar'
        data = Interpolator.interpolate(@wellformed)
        assert_equal('/home/doudou/src', data["autobuild"]["srcdir"])
        assert_equal('/home/doudou/build', data["autobuild"]["prefix"])
        assert_equal('envvar', data["autobuild"]["envvar"])
        assert_equal(10, data["autobuild"]["nice"])
        assert_kind_of(Fixnum, data["autobuild"]["nice"])
    end
end

