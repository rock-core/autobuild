require 'autobuild/test'

module Autobuild
    describe Package do
        describe "#apply_env" do
            attr_reader :package, :env
            before do
                @package = Package.new("pkg")
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
                assert_equal "trying to reset KEY to [\"OTHER_VALUE\"] in pkg but this conflicts with test already setting it to VALUE: Autobuild::Package::IncompatibleEnvironment", e.message
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

        describe "#fingerprint_generation" do
            attr_reader :package
            before do
                @pkg0 = Package.new('pkg0')
                @pkg0.importer = Importer.new \
                    interactive: false
                
                @pkg1 = Package.new('pkg1')
                @pkg1.importer = Importer.new \
                    interactive: false
                
                @dep_pkg0 = Package.new('dep_pkg0')
                @dep_pkg1 = Package.new('dep_pkg1')

                @dep_pkg0.importer = Importer.new \
                    interactive: false
                @dep_pkg1.importer = Importer.new \
                    interactive: false
                
            end

            it "return nil when the package's importer does not compute a fingerprint" do
                flexmock(@pkg0.importer).should_receive(:fingerprint).
                    and_return(nil)
                assert_nil @pkg0.fingerprint  
            end

            it "return importer's fingerprint when there are no dependencies" do
                flexmock(@pkg0.importer).should_receive(:fingerprint).
                    and_return("fingerprint_placeholder")
                assert_equal "fingerprint_placeholder", @pkg0.fingerprint  
            end

            it "returns nil if one of the dependencies has no fingerprint" do
                flexmock(@pkg0).should_receive(:dependencies).
                    and_return(['dep_pkg0', 'dep_pkg1'])

                flexmock(@pkg0.importer).should_receive(:fingerprint).
                    and_return("fingerprint_placeholder")
                flexmock(@dep_pkg0.importer).should_receive(:fingerprint).
                    and_return(nil)
                flexmock(@dep_pkg1.importer).should_receive(:fingerprint).
                    and_return("fingerprint_placeholder_pkg1")

                assert_nil @pkg0.fingerprint  
            end

            it "fingerprints should be the same no matter the order of the dependencies" do
                flexmock(@pkg0).should_receive(:dependencies).
                    and_return(['dep_pkg0', 'dep_pkg1'])

                flexmock(@pkg0.importer).should_receive(:fingerprint).
                    and_return("fingerprint_placeholder")
                flexmock(@dep_pkg0.importer).should_receive(:fingerprint).
                    and_return("fingerprint_placeholder_pkg0")
                flexmock(@dep_pkg1.importer).should_receive(:fingerprint).
                    and_return("fingerprint_placeholder_pkg1")

                fingerprint_pkg0_pk1 = @pkg0.fingerprint  

                flexmock(@pkg1).should_receive(:dependencies).
                    and_return(['dep_pkg1', 'dep_pkg0'])

                flexmock(@pkg1.importer).should_receive(:fingerprint).
                    and_return("fingerprint_placeholder")
                flexmock(@dep_pkg0.importer).should_receive(:fingerprint).
                    and_return("fingerprint_placeholder_pkg0")
                flexmock(@dep_pkg1.importer).should_receive(:fingerprint).
                    and_return("fingerprint_placeholder_pkg1")

                fingerprint_pkg1_pk0 = @pkg1.fingerprint  

                assert_equal fingerprint_pkg0_pk1, fingerprint_pkg1_pk0
            end

            it "returns expected fingerprint" do
                flexmock(@pkg0).should_receive(:dependencies).
                    and_return(['dep_pkg0', 'dep_pkg1'])

                flexmock(@pkg0.importer).should_receive(:fingerprint).
                    and_return("fingerprint_placeholder_pkg0")
                flexmock(@dep_pkg0.importer).should_receive(:fingerprint).
                    and_return("fingerprint_placeholder_dep_pkg0")
                flexmock(@dep_pkg1.importer).should_receive(:fingerprint).
                    and_return("fingerprint_placeholder_dep_pkg1")

                expected_fingerprint = Digest::SHA1.hexdigest("fingerprint_placeholder_pkg0fingerprint_placeholder_dep_pkg0fingerprint_placeholder_dep_pkg1")
                assert_equal expected_fingerprint, @pkg0.fingerprint  
            end

        end
    end
end

