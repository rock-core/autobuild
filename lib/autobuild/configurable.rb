require 'pathname'
require 'autobuild/timestamps'
require 'autobuild/environment'
require 'autobuild/package'
require 'autobuild/subcommand'
require 'shellwords'

module Autobuild
    # Base class for packages that require a configuration + build step.
    #
    # Child classes must provide a #configurestamp file which represents the
    # last configuration step done. This file is updated by a call to
    # #configure (see below)
    #
    # Three new methods are added, which can be reimplemented in child classes:
    # * +configure+ does configure the package. It is ran after all
    #   depended-upon packages are installed.
    # * +build+ is ran after +configure+ if the configure stamp and/or the
    #   source files have been updated. The #buildstamp stampfile represents when
    #   the last build has been done. The build must be done in the #builddir directory.
    # * +install+ is ran after +build+.
    #   
    class Configurable < Package
        class << self
            def builddir
                if @builddir
                    @builddir
                else
                    ancestors.each do |klass|
                        if result = klass.instance_variable_get(:@builddir)
                            return result
                        end
                    end
                    nil
                end
            end

            def builddir=(new)
                raise ConfigException, "absolute builddirs are not supported" if (Pathname.new(new).absolute?)
                raise ConfigException, "builddir must be non-nil and non-empty" if (new.nil? || new.empty?)
                @builddir = new
            end
        end
        @builddir = 'build'
        
        def builddir=(new)
            raise ConfigException, "absolute builddirs are not supported" if (Pathname.new(new).absolute?)
            raise ConfigException, "builddir must be non-empty" if new.empty?
            @builddir = new
        end
        # Returns the absolute builddir
        def builddir; File.expand_path(@builddir || self.class.builddir, srcdir) end

        # Build stamp
        # This returns the name of the file which marks when the package has been
        # successfully built for the last time. The path is absolute
        def buildstamp; "#{builddir}/#{STAMPFILE}" end

        def prepare_for_forced_build
            FileUtils.rm_f buildstamp
            FileUtils.rm_f configurestamp
        end

        def prepare_for_rebuild
            prepare_for_forced_build
            if File.exists?(builddir) && builddir != srcdir
                FileUtils.rm_rf builddir
            end
        end

        def ensure_dependencies_installed
            dependencies.each do |pkg|
                Rake::Task[Package[pkg].installstamp].invoke
            end
        end

        def prepare
            Autobuild.source_tree srcdir do |pkg|
                pkg.exclude << Regexp.new("^#{Regexp.quote(builddir)}")
                pkg.exclude << Regexp.new("^#{Regexp.quote(doc_dir)}") if doc_dir
            end

            super

            stamps = dependencies.map { |pkg| Autobuild::Package[pkg].installstamp }
            file configurestamp => stamps do
                isolate_errors do
                    ensure_dependencies_installed
                    configure
                end
            end
            task "#{name}-prepare" => configurestamp

            file buildstamp => [ srcdir, configurestamp ] do
                isolate_errors do
                    ensure_dependencies_installed
                    build
                end
            end
            task "#{name}-build" => buildstamp

            file installstamp => buildstamp
        end

        # Configure the builddir directory before starting make
        def configure
            if File.exists?(builddir) && !File.directory?(builddir)
                raise ConfigException, "#{builddir} already exists but is not a directory"
            end
            FileUtils.mkdir_p builddir if !File.directory?(builddir)

            yield

            Autobuild.touch_stamp(configurestamp)
        end

        # Do the build in builddir
        def build
        end
    end
end


