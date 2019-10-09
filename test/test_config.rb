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

    describe '#apply' do
        before do
            @packages = (0...4).map { |i| Autobuild::Package.new(i.to_s) }
            @tasks = @packages.map do |p|
                p.task("#{p.name}-build")
            end
        end

        it 'yield to the completion callback when a root task is completed' do
            @tasks[0].enhance @tasks[1..2]
            @tasks[1].enhance [@tasks[3]]
            @tasks[2].enhance [@tasks[3]]
            @packages.map(&:prepare)

            received = []
            Autobuild.apply(@packages.map(&:name), 'test', ['build']) do |pkg, phase|
                received << [pkg, phase]
            end
            assert_equal 4, received.size
            assert_equal [@packages[3], 'build'], received[0]
            assert_equal [[@packages[1], 'build'], [@packages[2], 'build']].to_set,
                         received[1, 2].to_set
            assert_equal [@packages[0], 'build'], received[3]
        end

        it 'yield to the completion callback even if the task fails' do
            @packages[0].depends_on @packages[1]
            @packages[0].depends_on @packages[2]
            @packages[1].depends_on @packages[3]
            @packages[2].depends_on @packages[3]
        end
    end
end
