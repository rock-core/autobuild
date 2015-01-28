require 'autobuild/test'
require 'fakefs/safe'
require 'flexmock'

describe Autobuild do

    describe "tool" do
        after do
            Autobuild.programs.delete('test')
        end

        it "should return the tool name by default" do
            assert_equal 'a_test_name', Autobuild.tool('a_test_name')
        end
        it "should return the default tool name as a string" do
            assert_equal 'a_test_name', Autobuild.tool(:a_test_name)
        end
        it "should be indifferent whether a tool is overriden using symbols or strings" do
            Autobuild.programs['test'] = 'a_test_name'
            assert_equal 'a_test_name', Autobuild.tool('test')
            assert_equal 'a_test_name', Autobuild.tool(:test)
            Autobuild.programs[:test] = 'a_test_name'
            assert_equal 'a_test_name', Autobuild.tool('test')
            assert_equal 'a_test_name', Autobuild.tool(:test)
        end
    end

    describe "tool_in_path" do
        before do
            FakeFS.activate!
            flexmock(Autobuild).should_receive(:tool).with('bla').and_return('a_test_name').by_default
            flexmock(ENV).should_receive('[]').with('PATH').and_return('/a/path')
            flexmock(ENV).should_receive('[]').with(any).pass_thru
            FileUtils.mkdir_p('/a/path')
        end
        after do
            FakeFS.deactivate!
            FakeFS::FileSystem.clear
            Autobuild.programs_in_path.delete('bla')
        end

        it "should raise ArgumentError if the tool is not present in path" do
            assert_raises(ArgumentError) { Autobuild.tool_in_path('bla') }
        end
        it "should raise ArgumentError if the tool is present in path but is not a file" do
            FileUtils.mkdir_p('/a/path/a_test_name')
            assert_raises(ArgumentError) { Autobuild.tool_in_path('bla') }
        end
        it "should raise ArgumentError if the tool is present in path but is not executable" do
            FileUtils.touch('/a/path/a_test_name')
            FileUtils.chmod(0, '/a/path/a_test_name')
            assert_raises(ArgumentError) { Autobuild.tool_in_path('bla') }
        end
        it "should return the full path to the resolved tool  ArgumentError if the tool is present in path but is not executable" do
            FileUtils.touch('/a/path/a_test_name')
            FileUtils.chmod(0755, '/a/path/a_test_name')
            assert_equal '/a/path/a_test_name', Autobuild.tool_in_path('bla')
        end
        it "should update the cache to the resolved value" do
            FileUtils.touch('/a/path/a_test_name')
            FileUtils.chmod(0755, '/a/path/a_test_name')
            Autobuild.tool_in_path('bla')
            assert_equal ['/a/path/a_test_name', 'a_test_name', ENV['PATH']], Autobuild.programs_in_path['bla'], "cached value mismatch"
        end
        it "should not re-hit the filesystem if the cache is up to date" do
            Autobuild.programs_in_path['bla'] = ['bla', 'a_test_name', ENV['PATH']]
            assert_equal 'bla', Autobuild.tool_in_path('bla')
        end
        it "should work fine if the tool is set to a full path" do
            flexmock(Autobuild).should_receive(:tool).with('bla').and_return('/another/path/a_test_name')
            FileUtils.mkdir_p('/another/path')
            FileUtils.touch('/another/path/a_test_name')
            FileUtils.chmod(0755, '/another/path/a_test_name')
            assert_equal '/another/path/a_test_name', Autobuild.tool_in_path('bla')
        end
    end
end


