require 'autobuild/test'

module Autobuild
    describe Reporting do
        describe ".report" do
            it "returns 'no errors' if there are none" do
                assert_equal [], Reporting.report {}
            end

            describe "on_package_failures: :raise" do
                before do
                    @package_e = Class.new(Autobuild::Exception).
                        exception('test exception')
                end
                after do
                    Autobuild::Package.clear
                end

                it "lets an Interrupt pass through" do
                    assert_raises(Interrupt) do
                        Reporting.report(on_package_failures: :raise) { raise Interrupt }
                    end
                end
                it "raises a package failure" do
                    flexmock(Reporting).should_receive(:error).never
                    e = assert_raises(@package_e.class) do
                        Reporting.report(on_package_failures: :raise) do
                            pkg = Autobuild::Package.new('test')
                            pkg.failures << @package_e
                            binding.pry
                        end
                    end
                    assert_equal @package_e, e
                end
                it "reports a package fatal error and raises it, even if an Interrupt has been raised" do
                    flexmock(Reporting).should_receive(:error).with(@package_e).once
                    e = assert_raises(@package_e.class) do
                        Reporting.report(on_package_failures: :raise) do
                            pkg = Autobuild::Package.new('test')
                            pkg.failures << @package_e
                            raise Interrupt
                        end
                    end
                    assert_same @package_e, e
                end
                it "combines multiple failures into a CompositeException error before raising it" do
                    other_package_e = Class.new(Autobuild::Exception).exception('test')
                    flexmock(Reporting).should_receive(:error).with(@package_e).once
                    flexmock(Reporting).should_receive(:error).with(other_package_e).once
                    e = assert_raises(CompositeException) do
                        Reporting.report(on_package_failures: :raise) do
                            pkg = Autobuild::Package.new('test')
                            pkg.failures << @package_e << other_package_e
                            raise Interrupt
                        end
                    end
                    assert_equal [@package_e, other_package_e], e.original_errors
                end
                it "reports package non-fatal errors and returns them" do
                    flexmock(@package_e, fatal?: false)
                    flexmock(Reporting).should_receive(:error).with(@package_e).once
                    assert_equal [@package_e], Reporting.report(on_package_failures: :raise) {
                            pkg = Autobuild::Package.new('test')
                            pkg.failures << @package_e
                            raise Interrupt }
                end
                it "reports package non-fatal errors and raises Interrupt if an Interrupt has been raised" do
                    flexmock(@package_e, fatal?: false)
                    flexmock(Reporting).should_receive(:error).with(@package_e).once
                    assert_raises(Interrupt) do
                        Reporting.report(on_package_failures: :raise) {
                            pkg = Autobuild::Package.new('test')
                            pkg.failures << @package_e
                            raise Interrupt }
                    end
                end
            end

            describe "on_package_failures: :exit" do
                before do
                    @package_e = Class.new(Autobuild::Exception).
                        exception('test exception')
                end

                it "lets an Interrupt pass through" do
                    assert_raises(Interrupt) do
                        Reporting.report(on_package_failures: :exit) do
                            raise Interrupt
                        end
                    end
                end
                it "reports package fatal errors and exits" do
                    flexmock(Reporting).should_receive(:error).with(@package_e).once
                    assert_raises(SystemExit) do
                        Reporting.report do
                            pkg = Autobuild::Package.new('test')
                            pkg.failures << @package_e
                        end
                    end
                end
                it "reports package non-fatal errors and exits, even if an Interrupt has been raised" do
                    flexmock(Reporting).should_receive(:error).with(@package_e).once
                    assert_raises(SystemExit) do
                        Reporting.report do
                            pkg = Autobuild::Package.new('test')
                            pkg.failures << @package_e
                            raise Interrupt
                        end
                    end
                end
                it "reports package non-fatal errors and returns them" do
                    flexmock(@package_e, fatal?: false)
                    flexmock(Reporting).should_receive(:error).with(@package_e).once
                    assert_equal [@package_e], Reporting.report {
                            pkg = Autobuild::Package.new('test')
                            pkg.failures << @package_e
                            raise Interrupt }
                end
                it "reports package non-fatal errors and raises Interrupt if an Interrupt has been raised" do
                    flexmock(@package_e, fatal?: false)
                    flexmock(Reporting).should_receive(:error).with(@package_e).once
                    assert_raises(Interrupt) do
                        Reporting.report {
                            pkg = Autobuild::Package.new('test')
                            pkg.failures << @package_e
                            raise Interrupt }
                    end
                end
            end

            describe "on_package_failures: :report" do
                before do
                    @package_e = Class.new(Autobuild::Exception).
                        exception('test exception')
                    @other_package_e = Class.new(Autobuild::Exception).
                        exception('test')
                end

                it "lets an Interrupt pass through" do
                    assert_raises(Interrupt) do
                        Reporting.report(on_package_failures: :report) { raise Interrupt }
                    end
                end
                it "reports package errors and returns them" do
                    flexmock(Reporting).should_receive(:error).with(@package_e).once
                    flexmock(Reporting).should_receive(:error).with(@other_package_e).once
                    assert_equal [@package_e, @other_package_e], Reporting.report(on_package_failures: :report) {
                            pkg = Autobuild::Package.new('test')
                            pkg.failures << @package_e << @other_package_e }
                end
                it "reports package errors and raises Interrupt if an interrupt was raised" do
                    flexmock(Reporting).should_receive(:error).with(@package_e).once
                    flexmock(Reporting).should_receive(:error).with(@other_package_e).once
                    assert_raises(Interrupt) do
                        Reporting.report(on_package_failures: :report) {
                            pkg = Autobuild::Package.new('test')
                            pkg.failures << @package_e << @other_package_e
                            raise Interrupt }
                    end
                end
            end
        end
    end
end

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

