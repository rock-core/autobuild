$LOAD_PATH << File.expand_path('../lib', File.dirname(__FILE__))
$LOAD_PATH << File.dirname(__FILE__)
require 'test/unit'
require 'conffile-generator'
require 'autobuild/options'
require 'autobuild/config'

class TC_Config < Test::Unit::TestCase
    def setup
        @conffile = ConffileGenerator.build(binding, 'dummy')
        @options_hash = File.open(@conffile) { |f| YAML.load(f) }
        @options = File.open(@conffile) { |f| Config.load(f, Options.default) }
    end

    def teardown
        ConffileGenerator.clean
    end

    def test_keys_to_sym
        symed = @options_hash.keys_to_sym

        pass_through = {}
        symed.each_recursive { |k, v|
            assert_kind_of(Symbol, k)
            pass_through[k] = true
        }

        assert(pass_through[:PATH])
        assert(pass_through[:prefix])
        assert(pass_through[:autobuild])
        assert_kind_of(String, symed[:autobuild][:srcdir])
    end
        
    def test_value_type
        assert_kind_of(String, $SRCDIR)
        assert_kind_of(Fixnum, $NICE)
        assert_equal(0, $NICE)
    end
end

