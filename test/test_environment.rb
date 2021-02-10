require 'autobuild/test'

module Autobuild
    describe Environment do
        before do
            @env = Environment.new
        end

        describe "an inherited environment variable" do
            before do
                Autobuild::ORIGINAL_ENV['AUTOBUILD_TEST'] = "val1:val0"
                @env = Environment.new
                @env.inherit 'AUTOBUILD_TEST'
            end
            describe "push_path" do
                it "does not re-read the inherited environment" do
                end
                it "adds the new path at the beginning of the variable, before the inherited environment" do
                    @env.push 'AUTOBUILD_TEST', 'newval1'
                    @env.push 'AUTOBUILD_TEST', 'newval0'
                    assert_equal 'newval1:newval0:val1:val0',
                                 @env.resolved_env['AUTOBUILD_TEST']
                end
            end
            describe "#env_add_path" do
                it "does not re-read the inherited environment" do
                    Autobuild::ORIGINAL_ENV['AUTOBUILD_TEST'] = 'val2:val3'
                    @env.add 'AUTOBUILD_TEST', 'newval'
                    assert_equal 'newval:val1:val0',
                                 @env.resolved_env['AUTOBUILD_TEST']
                end
                it "adds the new path at the end of the variable, before the inherited environment" do
                    @env.add 'AUTOBUILD_TEST', 'newval0'
                    @env.add 'AUTOBUILD_TEST', 'newval1'
                    assert_equal 'newval1:newval0:val1:val0',
                                 @env.resolved_env['AUTOBUILD_TEST']
                end
            end
            describe "#env_set" do
                it "does not reinitialize the inherited environment" do
                    Autobuild::ORIGINAL_ENV['AUTOBUILD_TEST'] = 'val2:val3'
                    @env.set 'AUTOBUILD_TEST', 'newval'
                    assert_equal 'newval:val1:val0', @env.resolved_env['AUTOBUILD_TEST']
                end
                it "resets the current value to the expected one" do
                    @env.set 'AUTOBUILD_TEST', 'newval0', 'newval1'
                    assert_equal 'newval0:newval1:val1:val0', @env.resolved_env['AUTOBUILD_TEST']
                    @env.set 'AUTOBUILD_TEST', 'newval2', 'newval3'
                    assert_equal 'newval2:newval3:val1:val0', @env.resolved_env['AUTOBUILD_TEST']
                end
            end
            describe "#env_clear" do
                it "completely unsets the variable" do
                    @env.clear 'AUTOBUILD_TEST'
                    assert_nil @env.resolved_env['AUTOBUILD_TEST']
                end
            end
        end

        describe "a not-inherited environment variable" do
            before do
                Autobuild::ORIGINAL_ENV['AUTOBUILD_TEST'] = "val1:val0"
                @env.reset 'AUTOBUILD_TEST'
            end

            describe "#env_push_path" do
                it "adds the new path at the beginning of the variable" do
                    @env.push 'AUTOBUILD_TEST', 'newval1'
                    @env.push 'AUTOBUILD_TEST', 'newval0'
                    assert_equal 'newval1:newval0',
                                 @env.resolved_env['AUTOBUILD_TEST']
                end
            end
            describe "#env_add_path" do
                it "adds the new path at the end of the variable" do
                    @env.add 'AUTOBUILD_TEST', 'newval0'
                    @env.add 'AUTOBUILD_TEST', 'newval1'
                    assert_equal 'newval1:newval0',
                                 @env.resolved_env['AUTOBUILD_TEST']
                end
            end
            describe "#env_clear" do
                it "completely unsets the variable" do
                    @env.clear 'AUTOBUILD_TEST'
                    assert_nil @env.resolved_env['AUTOBUILD_TEST']
                end
            end
        end

        describe "find_in_path" do
            before do
                @env = Environment.new
            end

            it "returns the first file matching the name in PATH by default" do
                @env.set 'PATH', @tempdir
                path = File.join(@tempdir, 'test')
                FileUtils.touch path
                assert_equal path, @env.find_in_path('test')
            end

            it "returns nil if the name cannot be found" do
                assert_nil @env.find_in_path('test')
            end

            it "ignores non-files" do
                other_dir = make_tmpdir
                @env.set 'PATH', @tempdir, other_dir
                FileUtils.mkdir File.join(@tempdir, 'test')
                path = File.join(other_dir, 'test')
                FileUtils.touch path
                assert_equal path, @env.find_in_path('test')
            end
        end

        describe "find_executable_in_path" do
            before do
                @env = Environment.new
            end

            it "returns the first executable file matching the name in PATH by default" do
                @env.set 'PATH', @tempdir
                path = File.join(@tempdir, 'test')
                FileUtils.touch path
                File.chmod 0o755, path
                assert_equal path, @env.find_executable_in_path('test')
            end

            it "returns nil if the name cannot be found" do
                assert_nil @env.find_executable_in_path('test')
            end

            it "ignores non-executable files" do
                other_dir = make_tmpdir
                @env.set 'PATH', @tempdir, other_dir
                FileUtils.touch File.join(@tempdir, 'test')
                path = File.join(other_dir, 'test')
                FileUtils.touch path
                File.chmod 0o755, path
                assert_equal path, @env.find_executable_in_path('test')
            end

            it "ignores non-files" do
                other_dir = make_tmpdir
                @env.set 'PATH', @tempdir, other_dir
                FileUtils.mkdir File.join(@tempdir, 'test')
                path = File.join(other_dir, 'test')
                FileUtils.touch path
                File.chmod 0o755, path
                assert_equal path, @env.find_executable_in_path('test')
            end
        end

        describe "environment_from_export" do
            before do
                @export = Environment::ExportedEnvironment.new(
                    Hash.new, [], Hash.new)
            end

            it "imports unset values from the base environment" do
                assert_equal Hash['BLA' => '1'], Environment.
                    environment_from_export(@export, 'BLA' => '1')
            end

            it "gets overriden by 'set' values" do
                @export.set['BLA'] = ['2']
                assert_equal Hash['BLA' => '2'], Environment.
                    environment_from_export(@export, 'BLA' => '1')
            end

            it "gets deleted by 'unset' values" do
                @export.unset << 'BLA'
                assert_equal Hash.new, Environment.
                    environment_from_export(@export, 'BLA' => '1')
            end

            it "injects the current value in the placeholder for 'update' values" do
                @export.update['BLA'] = [%w[a b $BLA c], []]
                assert_equal Hash['BLA' => 'a:b:1:c'], Environment.
                    environment_from_export(@export, 'BLA' => '1')
            end

            it "returns the without-inheritance value if the current env entry is unset" do
                @export.update['BLA'] = [%w[a b $BLA c], %w[d e f]]
                assert_equal Hash['BLA' => 'd:e:f'], Environment.
                    environment_from_export(@export, Hash.new)
            end
        end
    end
end
