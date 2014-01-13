module Autobuild
    class Ruby < ImporterPackage
        # The Rake task that is used to set up the package. Defaults to "default".
        # Set to nil to disable setup altogether
        attr_accessor :rake_setup_task
        # The Rake task that is used to generate documentation. Defaults to "doc".
        # Set to nil to disable documentation generation
        attr_accessor :rake_doc_task
        # The Rake task that is used to run tests. Defaults to "test".
        # Set to nil to disable tests for this package
        attr_accessor :rake_test_task

        def initialize(*args)
            self.rake_setup_task = "default"
            self.rake_doc_task   = "redocs"
            self.rake_test_task  = "test"

            super
            exclude << /\.so$/
            exclude << /Makefile$/
            exclude << /mkmf.log$/
            exclude << /\.o$/
            exclude << /doc$/
        end

        def with_doc
            doc_task do
                progress_start "generating documentation for %s", :done_message => 'generated documentation for %s' do
                    Autobuild::Subprocess.run self, 'doc',
                        Autoproj::CmdLine.ruby_executable,
                        Autoproj.find_in_path('rake'), rake_doc_task,
                        :working_directory => srcdir
                end
            end
        end

        def with_tests
            test_utility.task do
                progress_start "running tests for %s", :done_message => 'tests passed for %s' do
                    Autobuild::Subprocess.run self, 'test',
                        Autoproj::CmdLine.ruby_executable,
                        Autoproj.find_in_path('rake'), rake_test_task,
                        :working_directory => srcdir
                end
            end
        end

        def install
            progress_start "setting up Ruby package %s", :done_message => 'set up Ruby package %s' do
                Autobuild.update_environment srcdir
                # Add lib/ unconditionally, as we know that it is a ruby package.
                # Autobuild will add it only if there is a .rb file in the directory
                libdir = File.join(srcdir, 'lib')
                if File.directory?(libdir)
                    Autobuild.env_add_path 'RUBYLIB', libdir
                end

                if rake_setup_task && File.file?(File.join(srcdir, 'Rakefile'))
                    Autobuild::Subprocess.run self, 'post-install',
                        Autoproj::CmdLine.ruby_executable, Autoproj.find_in_path('rake'), rake_setup_task, :working_directory => srcdir
                end
            end
            super
        end

        def prepare_for_forced_build # :nodoc:
            super
            extdir = File.join(srcdir, 'ext')
            if File.directory?(extdir)
                Find.find(extdir) do |file|
                    next if file !~ /\<Makefile\>|\<CMakeCache.txt\>$/
                    FileUtils.rm_rf file
                end
            end
        end

        def prepare_for_rebuild # :nodoc:
            super
            extdir = File.join(srcdir, 'ext')
            if File.directory?(extdir)
                Find.find(extdir) do |file|
                    if File.directory?(file) && File.basename(file) == "build"
                        FileUtils.rm_rf file
                        Find.prune
                    end
                end
                Find.find(extdir) do |file|
                    if File.basename(file) == "Makefile"
                        Autobuild::Subprocess.run self, 'build', Autobuild.tool("make"), "-C", File.dirname(file), "clean"
                    end
                end
            end
        end

        def update_environment
            Autobuild.update_environment srcdir
            libdir = File.join(srcdir, 'lib')
            if File.directory?(libdir)
                Autobuild.env_add_path 'RUBYLIB', libdir
            end
        end
    end

    def self.ruby(spec, &proc)
        Ruby.new(spec, &proc)
    end
end

