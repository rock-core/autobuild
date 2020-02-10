require 'autobuild/test'
require 'timecop'

module Autobuild
    describe ProgressDisplay do
        after do
            Timecop.return
        end

        describe "#silent" do
            before do
                @io = StringIO.new
                @formatter = ProgressDisplay.new(@io)
            end

            it "should keep previous mode" do
                @formatter.silent = false
                @formatter.silent { }
                refute @formatter.silent?
            end
        end

        describe 'the progress mode' do
            before do
                @io = StringIO.new
                @display = ProgressDisplay.new(@io)
                @display.progress_period = 0
                @display.progress_start :key, 'start'
                @io.string.clear
                @io.rewind
            end
            it 'does not output any progress message if the mode is off' do
                @display.progress_mode = 'off'
                @display.progress :key, 'progress 0'
                assert @io.string.empty?
            end

            it 'clears the last message and replaces it with the new one if mode is single_line' do
                @display.progress_mode = 'single_line'
                @display.progress :key, 'progress 0'
                @display.progress :key, 'progress 1'
                expected = "#{TTY::Cursor.clear_screen_down}  progress 0"\
                           "#{TTY::Cursor.column(0)}"\
                           "#{TTY::Cursor.clear_screen_down}  progress 1"\
                           "#{TTY::Cursor.column(0)}"
                assert_equal expected, @io.string
            end

            it 'outputs messages on new lines if mode is newline' do
                @display.progress_mode = 'newline'
                @display.progress :key, 'progress 0'
                @display.progress :key, 'progress 1'
                assert_equal "  progress 0\n  progress 1\n", @io.string
            end
        end

        describe 'the progress period' do
            before do
                @io = StringIO.new
                @display = ProgressDisplay.new(@io)
                @display.progress_period = 1
                @display.progress_mode = 'newline'
            end

            it 'does not display progress messages that come quicker than the period' do
                Timecop.freeze(now = Time.now)
                @display.progress_start :key, 'start'
                Timecop.freeze(now + 0.1)
                @display.progress :key, 'progress 1'
                Timecop.freeze(now + 0.5)
                @display.progress :key, 'progress 2'
                Timecop.freeze(now + 1.01)
                @display.progress :key, 'progress 3'

                assert_equal "  start\n  progress 3\n", @io.string
            end

            it 'displays normal messages regardless of the period' do
                Timecop.freeze(now = Time.now)
                @display.progress_start :key, 'start'
                Timecop.freeze(now + 0.1)
                @display.message 'msg'

                assert_equal "  start\nmsg\n", @io.string
            end

            it 'displays start and stop messages regardless of the period' do
                Timecop.freeze(now = Time.now)
                @display.progress_start :key0, 'start 0'
                Timecop.freeze(now + 0.1)
                @display.progress_start :key1, 'start 1'
                Timecop.freeze(now + 0.2)
                @display.progress_done :key0, message: 'done 0'
                Timecop.freeze(now + 0.3)
                @display.progress_done :key1, message: 'done 1'

                assert_equal "  start 0\n  start 0, 1\n  done 0\n  done 1\n", @io.string
            end
        end

        describe "#format_grouped_messages" do
            before do
                @io = StringIO.new
                @formatter = ProgressDisplay.new(@io)
            end

            describe "without reaching the terminal width" do
                it "returns a single message as-is" do
                    lines = @formatter.format_grouped_messages(
                        ['simple message'], width: 200)
                    assert_equal ['  simple message'], lines
                end
                it "regroups same-prefix messages" do
                    lines = @formatter.format_grouped_messages(
                        ['message one', 'message two'], width: 200)
                    assert_equal ['  message one, two'], lines
                end
                it "will prefer longer prefixes to longer groups" do
                    lines = @formatter.format_grouped_messages(
                        ['a b c', 'a c d', 'a c e'], width: 200)
                    assert_equal ['  a b c', '  a c d, e'], lines
                end
                it "continues same-prefix messages on the next line if the width is reached" do
                    lines = @formatter.format_grouped_messages(
                        ['message one', 'message two'], width: 15)
                    assert_equal ['  message one,', '    two'], lines
                end
                it "is exact in the computation of the first line width" do
                    lines = @formatter.format_grouped_messages(
                        ['message one', 'message two', 'message twp'], width: 19)
                    assert_equal ['  message one, two,', '    twp'], lines
                end
                it "is exact in the computation of the following line's width" do
                    lines = @formatter.format_grouped_messages(
                        ['m 1', 'm 2', 'm 3', 'm 4', 'm 5'], width: 9)
                    assert_equal ['  m 1, 2,',
                                  '    3, 4,',
                                  '    5'], lines
                end
                it "is exact in the computation of the last line's width" do
                    lines = @formatter.format_grouped_messages(
                        ['m 1', 'm 2', 'm 3', 'm 4', 'm 5', 'm 66'], width: 9)
                    assert_equal ['  m 1, 2,',
                                  '    3, 4,',
                                  '    5, 66'], lines
                end
                it "continues other-prefix messages on the next line regardless of the width" do
                    lines = @formatter.format_grouped_messages(
                        ['one message', 'two message'], width: 100)
                    assert_equal ['  one message', '  two message'], lines
                end
            end
        end
    end
end
