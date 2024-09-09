require 'autobuild/test'

module Autobuild
    describe CMake do
        attr_reader :root_dir, :package, :prefix

        before do
            @root_dir = make_tmpdir
            @package = Autobuild.cmake :package
            prefix = File.join(root_dir, 'cmake-prefix')
            build  = File.join(root_dir, 'cmake-build')
            log    = File.join(prefix, 'log')

            package.srcdir = File.join(root_dir, 'cmake')
            FileUtils.mkdir_p package.srcdir
            package.prefix = prefix
            package.logdir = log
            package.builddir = build
        end

        def make_cmake_lists(contents)
            File.open(File.join(package.srcdir, 'CMakeLists.txt'), 'w') do |io|
                io.puts "cmake_minimum_required(VERSION 3.0)"
                io.puts contents
            end
        end

        it "runs cmake, builds and installs" do
            FileUtils.touch File.join(package.srcdir, 'contents.txt')
            make_cmake_lists("install(FILES contents.txt DESTINATION txt)")
            flexmock(package).should_receive(:configure).
                once.pass_thru
            flexmock(Autobuild).should_receive(:make_subcommand).
                with(package, 'build').with_block.once.pass_thru
            # prepare is for the gnumake detection, which is cached
            flexmock(package).should_receive(:run).
                with('prepare', any, any).
                at_most.once.pass_thru
            flexmock(package).should_receive(:run).
                with('configure', any, any, any, any, package.srcdir).
                once.pass_thru
            flexmock(package).should_receive(:run).
                with('build', 'cmake', '.').
                once.pass_thru
            flexmock(package).should_receive(:run).
                with('build', 'make', any).with_block.
                once.pass_thru
            flexmock(package).should_receive(:run).
                with('install', 'make', any, 'install').
                once.pass_thru
            prepare_and_build_package(package)
        end

        describe "test_args" do
            it "use -V as the default arg" do
                assert_equal ["-V"], package.test_args
            end

            it "allows setting global arguments" do
                Autobuild::CMake.test_args << "--arg1"
                foo = Autobuild.cmake :foo
                assert_equal ["-V", "--arg1"], foo.test_args
                Autobuild::CMake.test_args.replace(["-V"])
            end

            it "allows setting instance arguments" do
                package.test_args << "--arg2"
                assert_equal ["-V", "--arg2"], package.test_args
            end

            it "forwards arguments to make test target" do
                package.test_args << "--arg" << "value with spaces"
                package.test_utility.enabled = true
                package.test_utility.available = true
                package.test_utility.no_results = true

                flexmock(package).should_receive(:run)
                                 .with(
                                     "test",
                                     any,
                                     any,
                                     "test",
                                     'ARGS="-V" "--arg" "value with spaces"',
                                     working_directory: package.builddir
                                 ).once

                package.with_tests.invoke
            end

            it "does not pass test arguments to doc target" do
                package.doc_utility.enabled = true
                package.doc_utility.available = true
                package.doc_utility.no_results = true

                flexmock(package).should_receive(:run)
                                 .with(
                                     "doc",
                                     any,
                                     any,
                                     "doc",
                                     working_directory: package.builddir
                                 ).once

                package.with_doc.invoke
            end
        end

        describe "delete_obsolete_files_in_prefix?" do
            it "removes files in the target prefix that are not present in the manifest" do
                FileUtils.touch File.join(package.srcdir, 'contents.txt')
                FileUtils.mkdir_p package.prefix
                FileUtils.touch File.join(package.prefix, 'obsolete.txt')
                make_cmake_lists("install(FILES contents.txt DESTINATION txt)")
                package.delete_obsolete_files_in_prefix = true
                prepare_and_build_package(package)

                refute File.file?(File.join(package.prefix, 'obsolete.txt'))
                assert File.file?(File.join(package.prefix, 'txt', 'contents.txt'))
            end
            it "keeps the logs" do
                FileUtils.touch File.join(package.srcdir, 'contents.txt')
                make_cmake_lists("install(FILES contents.txt DESTINATION txt)")
                package.delete_obsolete_files_in_prefix = true
                prepare_and_build_package(package)
                assert File.file?(File.join(package.logdir, 'package-build.log'))
            end
        end

        describe "#defines_changed?" do
            it "returns true if the cache has no value for an expected define" do
                assert package.defines_changed?(
                    Hash['TEST' => 'ON'],
                    "CMAKE_BUILD_TYPE:STRING=Debug\nOTHER:BOOL=ON")
            end
            it "returns true if the cache has a different value than the expected define" do
                assert package.defines_changed?(
                    Hash['CMAKE_BUILD_TYPE' => 'Release'],
                    "CMAKE_BUILD_TYPE:STRING=Debug\nOTHER:BOOL=ON")
            end
            it "returns false if the cache has an equivalent value than the expected define" do
                refute package.defines_changed?(
                    Hash['CMAKE_BUILD_TYPE' => 'Debug'],
                    "CMAKE_BUILD_TYPE:STRING=Debug\nOTHER:BOOL=ON")
            end
        end

        describe "coverage" do
            attr_reader :test_handler
            attr_reader :test_task

            before do
                klass = Class.new do
                    def test; end
                    def coverage; end
                end
                @test_handler = klass.new
                @package.test_utility.enabled = true
                @package.test_utility.available = true
                @package.test_utility.no_results = true
                @test_task = @package.with_tests { test_handler.test }
                flexmock(@package).should_receive(:run).at_most.once
            end

            it "calls coverage block after test task" do
                @package.test_utility.coverage_enabled = true
                @package.with_coverage { test_handler.coverage }
                flexmock(test_handler).should_receive(:test).once.ordered
                flexmock(test_handler).should_receive(:coverage).once.ordered

                test_task.invoke
            end

            it "doesn't call coverage block if coverage is disabled" do
                @package.test_utility.coverage_enabled = false
                @package.with_coverage { test_handler.coverage }
                flexmock(test_handler).should_receive(:test).once
                flexmock(test_handler).should_receive(:coverage).never

                test_task.invoke
            end

            it "doesn't override an existing coverage block" do
                @package.test_utility.coverage_enabled = true
                @package.with_coverage { test_handler.coverage }
                @package.with_coverage { raise }
                flexmock(test_handler).should_receive(:coverage).once
                @package.coverage_block.call
            end
        end

        describe 'fingerprint' do
            before do
                importer = flexmock
                @importer_fingerprint = 'abc'
                importer.should_receive(:fingerprint).with(@package).
                         and_return { @importer_fingerprint }
                @package.importer = importer
            end

            it 'changes the fingerprint if the importer\'s change' do
                old = @package.fingerprint
                @importer_fingerprint = 'cde'
                refute_equal old, @package.fingerprint
            end

            it 'changes the fingerprint if the global defines change' do
                old = @package.fingerprint
                @package.define 'A', 'B'
                refute_equal old, @package.fingerprint
            end

            it 'changes the fingerprint if the local defines change' do
                old = @package.fingerprint
                @package.define 'A', 'B'
                refute_equal old, @package.fingerprint
            end

            it 'is not sensitive to the defines order' do
                @package.define 'A', 'B'
                @package.define 'C', 'D'
                a = @package.fingerprint
                @package.defines.clear
                @package.define 'C', 'D'
                @package.define 'A', 'B'
                assert_equal a, @package.fingerprint
            end
        end
    end
end
