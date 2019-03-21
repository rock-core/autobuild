require 'autobuild/test'
require 'autobuild/environment'
require 'fakefs/safe'

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
            flexmock(Autobuild).should_receive(:tool).with('bla').and_return('a_test_name').by_default
            @env = Autobuild::Environment.new
            @env.set 'PATH', @tempdir
        end
        after do
            Autobuild.programs_in_path.delete('bla')
        end

        def full_tool_path
            File.join(@tempdir, 'a_test_name')
        end

        def create_test_file
            FileUtils.touch(full_tool_path)
        end

        def create_test_executable
            create_test_file
            FileUtils.chmod 0o755, full_tool_path
        end

        it "should raise ArgumentError if the tool is not present in path" do
            assert_raises(ArgumentError) { Autobuild.tool_in_path('bla', env: @env) }
        end
        it "should raise ArgumentError if the tool is present in path but is not a file" do
            FileUtils.mkdir_p(full_tool_path)
            assert_raises(ArgumentError) { Autobuild.tool_in_path('bla', env: @env) }
        end
        it "should raise ArgumentError if the tool is present in path but is not executable" do
            create_test_file
            assert_raises(ArgumentError) { Autobuild.tool_in_path('bla', env: @env) }
        end
        it "should return the full path to the resolved tool if the tool is present in path and is executable" do
            create_test_executable
            assert_equal full_tool_path, Autobuild.tool_in_path('bla', env: @env)
        end
        it "should update the cache to the resolved value" do
            create_test_executable
            Autobuild.tool_in_path('bla', env: @env)
            assert_equal [full_tool_path, 'a_test_name', @tempdir], Autobuild.programs_in_path['bla'], "cached value mismatch"
        end
        it "should not re-hit the filesystem if the cache is up to date" do
            Autobuild.programs_in_path['bla'] = ['bla', 'a_test_name', @tempdir]
            assert_equal 'bla', Autobuild.tool_in_path('bla', env: @env)
        end
        it "should work fine if the tool is set to a full path" do
            flexmock(Autobuild).should_receive(:tool).with('bla').and_return(full_tool_path)
            create_test_executable
            assert_equal full_tool_path, Autobuild.tool_in_path('bla', env: @env)
        end
    end
end
