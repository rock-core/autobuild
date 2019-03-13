require 'autobuild/test'

module Autobuild
    describe ProgressDisplay do
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
