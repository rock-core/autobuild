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
            attr_reader :builddir
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
        def builddir; File.expand_path(@builddir || Configurable.builddir, srcdir) end

        # Build stamp
        # This returns the name of the file which marks when the package has been
        # successfully built for the last time. The path is absolute
        def buildstamp; "#{builddir}/#{STAMPFILE}" end

        def initialize(options)
            super

            Autobuild.update_environment(prefix)
        end

        def prepare_for_forced_build
            FileUtils.rm_f buildstamp
            FileUtils.rm_f configurestamp
        end

        def prepare_for_rebuild
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
            super

            stamps = dependencies.map { |p| Package[p.to_s].installstamp }
            file configurestamp => stamps
            file configurestamp do
                ensure_dependencies_installed
                configure
            end
            task "#{name}-prepare" => configurestamp

            Autobuild.source_tree srcdir do |pkg|
		pkg.exclude << Regexp.new("^#{Regexp.quote(builddir)}")
                pkg.exclude << Regexp.new("^#{doc_dir}") if doc_dir
	    end

            file buildstamp => [ srcdir, configurestamp ] do 
                ensure_dependencies_installed
                build
            end
            task "#{name}-build" => buildstamp

            file installstamp => buildstamp do 
                install
                Autobuild.update_environment(prefix)
            end
        end

        # Configure the builddir directory before starting make
        def configure
            Autobuild.touch_stamp(configurestamp)
        end

        # Do the build in builddir
        def build
        end

        # Install the result in prefix
        def install
            Autobuild.touch_stamp(installstamp)
        end
    end
end


