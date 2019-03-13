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
                with(package, 'build', Proc).once.pass_thru
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
                with('build', 'make', any, Proc).
                once.pass_thru
            flexmock(package).should_receive(:run).
                with('install', 'make', any, 'install').
                once.pass_thru
            prepare_and_build_package(package)
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
    end
end
