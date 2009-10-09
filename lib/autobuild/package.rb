require 'autobuild/timestamps'
require 'autobuild/environment'
require 'autobuild/subcommand'

module Autobuild
    TARGETS = %w{import prepare build}
    
    # Basic block for the autobuilder
    #
    # The build is done in three phases:
    #   - import
    #   - prepare
    #   - build & install
    #
    # In the first stage checks the source out and/or updates it.
    #
    # In the second stage, packages create their dependency structure to handle
    # specific build systems. For instance, it is there that build systems like
    # CMake are handled so that reconfiguration happens if needed. In the same
    # way, it is there that code generation will happen as well.
    #
    # Finally, the build stage actually calls the package's build targets (of
    # the form "package_name-build", which will trigger the build if needed.
    #
    # <b>Autodetecting dependencies</b>
    # There are two sides in dependency autodetection. The first side is that
    # packages must declare what they provide. One example is the handling of
    # pkgconfig dependencies: packages must declare that they provide a
    # pkgconfig definition. This side of the autodetection must be done just
    # after the package's import, by overloading the #import method:
    #
    #   def import
    #     super
    #
    #     # Do autodetection and call Package#provides
    #   end
    #
    # Note that, in most cases, the overloaded import method *must* begin with
    # "super".
    #
    # The other side is the detection itself. That must be done by overloading
    # the #prepare method.
    class Package
	@@packages = {}
	@@provides = {}

	# the package name
	attr_reader     :name
	# set the source directory. If a relative path is given,
	# it is relative to Autobuild.srcdir. Defaults to #name
	attr_writer     :srcdir
	# set the installation directory. If a relative path is given,
	# it is relative to Autobuild.prefix. Defaults to ''
	attr_writer :prefix
	
	# Sets importer object for this package. Defined for backwards compatibility.
	# Use the #importer attribute instead
	def import=(value)
	    @importer = value
	end
	# Sets an importer object for this package
	attr_accessor :importer

	# The list of packages this one depends upon
	attr_reader :dependencies

	# Absolute path to the source directory. See #srcdir=
	def srcdir; File.expand_path(@srcdir || name, Autobuild.srcdir) end
	# Absolute path to the installation directory. See #prefix=
	def prefix; File.expand_path(@prefix || '', Autobuild.prefix) end

	# The file which marks when the last sucessful install
	# has finished. The path is absolute
	#
	# A package is sucessfully built when it is installed
	def installstamp; "#{Autobuild.logdir}/#{name}-#{STAMPFILE}" end

	def initialize(spec)
	    @dependencies   = Array.new
	    @provides       = Array.new

	    if Hash === spec
		name, depends = spec.to_a.first
	    else
		name, depends = spec, nil
	    end

	    name = name.to_s
	    @name = name
	    raise ConfigException, "package #{name} is already defined" if Autobuild::Package[name]
	    @@packages[name] = self

	    # Call the config block (if any)
	    yield(self) if block_given?

            @doc_dir        ||= 'doc'
            @doc_target_dir ||= name
	    
	    # Declare the installation stampfile
	    file installstamp do
		Dir.chdir(srcdir) do
		    Autobuild.apply_post_install(name, @post_install)
		end
	    end
	    # Add dependencies declared in spec
	    depends_on *depends if depends

	    # Define the import task
	    task "#{name}-import" do import end
	    task :import => "#{name}-import"

	    # Define the prepare task
	    task "#{name}-prepare" => "#{name}-import" do prepare end
	    task :prepare => "#{name}-prepare"

	    task "#{name}-build" => ["#{name}-prepare", installstamp]
	    task :build => "#{name}-build"

	    task(name) do
		Rake::Task["#{name}-import"].invoke
		Rake::Task["#{name}-prepare"].invoke
		Rake::Task["#{name}-build"].invoke
                if has_doc? && !Autobuild.no_doc
                    Rake::Task["#{name}-doc"].invoke
                end
	    end
	    task :default => name
	end

        # Call the importer if there is one. Autodetection of "provides" should
        # be done there as well. See the documentation of Autobuild::Package for
        # more information.
	def import; @importer.import(self) if @importer end
        # Create all the dependencies required to reconfigure and/or rebuild the
        # package when required. The package's build target is called
        # "package_name-build".
	def prepare
            super if defined? super
            Autobuild.update_environment prefix
        end

        # Directory in which the documentation target will have generated the
        # documentation (if any). The interpretation of relative directories
        # is package-specific. The default implementation interpret them
        # as relative to the source directory, but packages like CMake will
        # interpret them as relative to their build directories.
        attr_accessor :doc_dir

        # Directory in which the documentation target should install the
        # documentation. If it is relative, it is interpreted as relative to
        # the prefix directory.
        attr_accessor :doc_target_dir

        # Defines a documentation generation task. The documentation is first
        # generated by the given block, and then installed. The local attribute
        # #doc_dir defines where the documentation is generated by the
        # package's build system, and the #doc_target_dir and
        # Autobuild.doc_prefix attributes define where it should be installed.
        #
        # The block is invoked in the package's source directory
        #
        # In general, specific package types define a meaningful #with_doc
        # method which calls this method internally.
        def doc_task
            task "#{name}-doc" => "#{name}-build" do
                @installed_doc = false
                catch(:doc_disabled) do
                    begin
                        Dir.chdir(srcdir) do
                            yield if block_given?
                        end

                        unless @installed_doc
                            install_doc
                        end

                    rescue Exception => e
                        if Autobuild.doc_errors
                            raise
                        else
                            STDERR.puts "W: failed to generate documentation for #{name}"
                            if e.kind_of?(SubcommandFailed)
                                STDERR.puts "W: see #{e.logfile} for more details"
                            end
                        end
                    end
                end
            end

            task :doc => "#{name}-doc"
        end

        def install_doc(relative_to = srcdir)
            full_doc_prefix = File.expand_path(Autobuild.doc_prefix, Autobuild.prefix)
            doc_target_dir  = File.expand_path(self.doc_target_dir, full_doc_prefix)
            doc_dir         = File.expand_path(self.doc_dir, relative_to)
            FileUtils.rm_rf   doc_target_dir
            FileUtils.mkdir_p File.dirname(doc_target_dir)
            FileUtils.cp_r    doc_dir, doc_target_dir

            @installed_doc = true
        end

        # Can be called in the doc_task implementation to announce that the
        # documentation is to be disabled for that package. This is mainly used
        # when a runtime check is necessary to know if a package has
        # documentation or not.
        def doc_disabled
            throw :doc_disabled
        end

        # True if a documentation task is defined for this package
        def has_doc?
            !!Rake.application.lookup("#{name}-doc")
        end

	def post_install(*args, &block)
	    if args.empty?
		@post_install = block
	    elsif !block
		@post_install = args
	    else
		raise ArgumentError, "cannot set both arguments and block"
	    end
	end

	# This package depends on +packages+. It means that its build will
        # always be triggered after the packages listed in +packages+ are built
        # and installed.
	def depends_on(*packages)
	    packages.each do |p|
		p = p.to_s
		next if p == name
		unless Package[p]
		    raise ConfigException.new(name), "package #{p} not defined"
		end
		file installstamp => Package[p].installstamp
		task "#{name}-import"  => "#{p}-import"
		task "#{name}-prepare" => "#{p}-prepare"
		@dependencies << p
	    end
	end

	# Declare that this package provides +packages+. In effect, the names
        # listed in +packages+ are aliases for this package.
	def provides(*packages)
	    packages.each do |p|
		p = p.to_s
		next if p == name
		@@provides[p] = self 
		task p => name
		task "#{p}-import" => "#{name}-import"
		task "#{p}-prepare" => "#{name}-prepare"
		task "#{p}-build" => "#{name}-build"
		@provides << p
	    end
	end

	# Iterates on all available packages
	# if with_provides is true, includes the list
	# of package aliases
	def self.each(with_provides = false, &p)
	    @@packages.each(&p) 
	    @@provides.each(&p) if with_provides
	end

	# Gets a package from its name
	def self.[](name)
	    @@packages[name.to_s] || @@provides[name.to_s]
	end
    end

    def self.package_set(spec)
	spec.each do |name, packages|
	    Autobuild::TARGETS.each do |target|
		task "#{name}-#{target}" => packages.map { |dep| "#{dep}-#{target}" }
	    end
	end
    end
end

