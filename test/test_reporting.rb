$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__))
require 'test/unit'
require 'tools'

require 'autobuild'
require 'tmpdir'
require 'fileutils'
require 'flexmock/test_unit'

class TC_Reporting < Test::Unit::TestCase
    def test_format_progress_message_does_not_touch_messages_without_prefix
        assert_equal "a | b | c",
            Autobuild.format_progress_message(%w{a b c})
    end
    def test_format_progress_message_find_common_prefix_at_beginning
        assert_equal "X a, b | c",
            Autobuild.format_progress_message(["X a", "X b", "c"])
    end
    def test_format_progress_message_picks_up_bigger_prefix
        assert_equal "X a | X y b, c | d",
            Autobuild.format_progress_message(["X a", "X y b", "X y c", "d"])
    end
    def test_format_progress_message_prefix_comparison_uses_string_length
        assert_equal "X mmmmmmmmmm a, b | X my x c | d",
            Autobuild.format_progress_message(["X mmmmmmmmmm a", "X mmmmmmmmmm b", "X my x c", "d"])
    end
end

