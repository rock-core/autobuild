require 'autobuild/test'

class TC_Reporting < Minitest::Test
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
    def test_package_message_with_marker_inside_token
        package = Autobuild::Package.new('pkg')
        assert_equal 'patching pkg: unapplying', package.process_formatting_string('patching %s: unapplying')
    end
    def test_package_message_with_marker_at_beginning
        package = Autobuild::Package.new('pkg')
        assert_equal 'pkg unapplying', package.process_formatting_string('%s unapplying')
    end
    def test_package_message_with_marker_at_end
        package = Autobuild::Package.new('pkg')
        assert_equal 'patching pkg', package.process_formatting_string('patching %s')
    end
    def test_package_message_without_formatting
        flexmock(Autobuild).should_receive('color').never
        package = Autobuild::Package.new('pkg')
        assert_equal 'patching a package pkg', package.process_formatting_string('patching a package %s')
    end
    def test_package_message_with_formatting
        flexmock(Autobuild).should_receive('color').with('patching a package', :bold, :red).and_return('|patching a package|').once
        package = Autobuild::Package.new('pkg')
        assert_equal '|patching a package| pkg', package.process_formatting_string('patching a package %s', :bold, :red)
    end
end

