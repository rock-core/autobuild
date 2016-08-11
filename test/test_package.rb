require 'autobuild/test'

module Autobuild
    describe Package do
        describe "#apply_env" do
            attr_reader :package, :env
            before do
                @package = Package.new
                @env = flexmock(base: Environment)
            end
            it "applies stored environment operations to the given environment object" do
                package.env_set 'KEY', 'VALUE'
                env.should_receive(:set).with('KEY', 'VALUE')
                package.apply_env(env)
            end
            it "raises IncompatibleEnvironment on conflicting 'set' operations" do
                package.env_set 'KEY', 'VALUE'
                package.env_set 'KEY', 'OTHER_VALUE'
                env.should_receive(:set).once
                assert_raises(Package::IncompatibleEnvironment) do
                    package.apply_env(env)
                end
            end
            it "does not apply the same op twice" do
                package.env_set 'KEY', 'VALUE'
                package.env_set 'KEY', 'VALUE'
                env.should_receive(:set).with('KEY', 'VALUE').once
                package.apply_env(env)
            end
            it "can be given the current set state to check against" do
                package.env_set 'KEY', 'OTHER_VALUE'
                env.should_receive(:set).never
                e = assert_raises(Package::IncompatibleEnvironment) do
                    package.apply_env(env, Hash['KEY'=> [flexmock(name: 'test'), 'VALUE']])
                end
                assert_equal "trying to reset KEY to [\"OTHER_VALUE\"] which conflicts with test already setting it to VALUE: Autobuild::Package::IncompatibleEnvironment", e.message
            end
            it "registers the set operations on the given 'set' Hash" do
                package.env_set 'KEY', 'VALUE'
                env.should_receive(:set)

                set_hash = Hash.new
                package.apply_env(env, set_hash)
                assert_equal Hash['KEY' => [package, ['VALUE']]], set_hash
            end
            it "registers the applied operations on the given op array" do
                package.env_set 'KEY', 'VALUE'
                env.should_receive(:set)
                set_hash = Hash.new

                ops = Array.new
                assert_same ops, package.apply_env(env, Hash.new, ops)
                assert_equal [Package::EnvOp.new(:set, 'KEY', ['VALUE'])], ops
            end
            it "returns the applied operations" do
                package.env_set 'KEY', 'VALUE'
                env.should_receive(:set)
                assert_equal [Package::EnvOp.new(:set, 'KEY', ['VALUE'])], package.apply_env(env)
            end
        end

        describe "#resolve_dependency_env" do
            attr_reader :package
            before do
                @package = Package.new
            end

            it "applies the environment of all its (recursive) dependencies and returns ops" do
                pkg0 = Package.new('pkg0')
                pkg1 = Package.new('pkg1')
                flexmock(package).should_receive(:all_dependencies).
                    and_return(['pkg0', 'pkg1'])

                env, set, ops = flexmock, flexmock, flexmock
                flexmock(pkg0).should_receive(:apply_env).with(env, set, ops).
                    and_return(ops)
                flexmock(pkg1).should_receive(:apply_env).with(env, set, ops).
                    and_return(ops)
                assert_equal ops, package.resolve_dependency_env(env, set, ops)
            end
        end
    end
end

