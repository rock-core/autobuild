require 'pathname'
require 'autobuild/timestamps'
require 'autobuild/environment'
require 'autobuild/package'
require 'autobuild/subcommand'
require 'shellwords'

module Autobuild
    def self.autotools(opts, &proc)
        Autotools.new(opts, &proc)
    end
        
    # 
    # ==== Handles autotools-based packages
    #
    # == Used programs (see <tt>Autobuild.programs</tt>)
    # Autotools will use the 'aclocal', 'autoheader', 'autoconf' and 'automake'
    # programs defined on Autobuild.programs. autoheader is disabled by default,
    # aclocal, autoconf and automake use are autodetected.
    #
    # To override this default behaviour on a per-package basis, use Autotools#use
    #
    class Autotools < Package
        attr_accessor   :using
        attr_accessor   :configureflags
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
        def builddir; File.expand_path(@builddir || Autotools.builddir, srcdir) end

        # Build stamp
        # This returns the name of the file which marks when the package has been
        # successfully built for the last time. The path is absolute
        def buildstamp; "#{builddir}/#{STAMPFILE}" end

        def initialize(options)
            @using = Hash.new
	    @configureflags = []

            super
        end
        
        def install_doc(relative_to = builddir)
            super(relative_to)
        end

        # Declare that the given target can be used to generate documentation
        def with_doc(target = 'doc')
            doc_task do
                Dir.chdir(builddir) do
                    Autobuild.progress "generating documentation for #{name}"
                    Subprocess.run(self, 'doc', Autobuild.tool(:make), "-j#{parallel_build_level}", target)
                    yield if block_given?
                end
            end
        end

	# Overrides the default behaviour w.r.t. autotools script generation
	#
	# Use it like that:
	# * to force a generation step (skipping autodetection), do
	#     pkg.use <program> => true
	#   For instance, for aclocal
	#     pkg.use :aclocal => true
	#
	# * to force a generation step, overriding the program defined on Autobuild
	#     pkg.use <program> => true
	#   For instance, for autoconf
	#     pkg.use :autoconf => 'my_autoconf_program'
	#
	# * to disable a generation step, do
	#     pkg.use <program> => false
	#   For instance, for automake
	#     pkg.use :automake => false
	#
	# * to restore autodetection, do
	#     pkg.use <program> => nil
	#   For instance, for automake
	#     pkg.use :automake => nil
	#
        def use(*programs)
            programs = *programs
            if !programs.kind_of?(Hash)
                programs = Array[*programs].inject({}) do |programs, spec|
                    programs[spec.first] = spec.last
                    programs
                end
            end
            programs.each do |name, opt|
                using[name.to_sym] = opt
            end

            nil
        end

        def depends_on(*packages)
            super
            stamps = packages.collect { |p| Package[p.to_s].installstamp }
            file "#{builddir}/config.status" => stamps
        end

        def ensure_dependencies_installed
            dependencies.each do |pkg|
                Rake::Task[Package[pkg].installstamp].invoke
            end
        end

        def prepare
            super

	    configureflags.flatten!

	    # Check if config.status has been generated with the
	    # same options than the ones in configureflags
	    config_status = "#{builddir}/config.status"

	    force_reconfigure = false
	    if File.exists?(config_status)
		output = IO.popen("#{config_status} --version").readlines.grep(/with options/).first.chomp
		raise "invalid output of config.status --version" unless output =~ /with options "(.*)"$/
		options = Shellwords.shellwords($1)

		# Add the --prefix option to the configureflags array
		testflags = ["--prefix=#{prefix}"] + Array[*configureflags]
		old_opt = options.find   { |o| !testflags.include?(o) }
		new_opt = testflags.find { |o| !options.include?(o) }
		if old_opt || new_opt
		    File.rm_f config_status # to force reconfiguration
		end
	    end

            file config_status => regen do
                ensure_dependencies_installed
                configure
            end

            Autobuild.source_tree srcdir do |pkg|
		pkg.exclude << Regexp.new("^#{Regexp.quote(builddir)}")
	    end
            file buildstamp => [ srcdir, "#{builddir}/config.status" ] do 
                ensure_dependencies_installed
                build
            end
            task "#{name}-build" => installstamp

            file installstamp => buildstamp do 
                install
            end

            Autobuild.update_environment(prefix)
        end

    private
        # Adds a target to rebuild the autotools environment
        def regen(confsource = nil)
	    conffile = "#{srcdir}/configure"
	    if confsource
		file conffile => confsource
	    elsif confext = %w{.ac .in}.find { |ext| File.exists?("#{conffile}#{ext}") }
		file conffile => "#{conffile}#{confext}"
	    else
		raise PackageException.new(name), "neither configure.ac nor configure.in present in #{srcdir}"
	    end

            file conffile do
                Dir.chdir(srcdir) {
                    if using[:autogen].nil?
                        using[:autogen] = %w{autogen autogen.sh}.find { |f| File.exists?(f) }
                    end

                    Autobuild.progress "generating build system for #{name}"
                    if using[:autogen]
                        Subprocess.run(self, 'configure', File.expand_path(using[:autogen]))
                    else
                        # Autodetect autoconf/aclocal/automake
                        #
                        # Let the user disable the use of autoconf explicitely by using 'false'.
                        # 'nil' means autodetection
                        using[:autoconf] = true if using[:autoconf].nil?
                        using[:aclocal] = using[:autoconf] if using[:aclocal].nil?
                        if using[:automake].nil?
                            using[:automake] = File.exists?(File.join(srcdir, 'Makefile.am'))
                        end

                        [ :aclocal, :autoconf, :autoheader, :automake ].each do |tool|
                            if tool_flag = using[tool]
				tool_program = if tool_flag.respond_to?(:to_str)
						   tool_flag.to_str
					       else; Autobuild.tool(tool)
					       end

                                Subprocess.run(self, 'configure', tool_program)
                            end
                        end
                    end
                end
            end

            return conffile
        end

        # Configure the builddir directory before starting make
        def configure
            if File.exists?(builddir) && !File.directory?(builddir)
                raise ConfigException, "#{builddir} already exists but is not a directory"
            end

            FileUtils.mkdir_p builddir if !File.directory?(builddir)
            Dir.chdir(builddir) {
                command = [ "#{srcdir}/configure", "--no-create", "--prefix=#{prefix}" ]
                command += Array[*configureflags]
                
                Autobuild.progress "configuring build system for #{name}"
                Subprocess.run(self, 'configure', *command)
            }
        end

        # Do the build in builddir
        def build
            Dir.chdir(builddir) {
                Autobuild.progress "building #{name}"
                Subprocess.run(self, 'build', './config.status')
                Subprocess.run(self, 'build', Autobuild.tool(:make), "-j#{parallel_build_level}")
            }
            Autobuild.touch_stamp(buildstamp)
        end

        # Install the result in prefix
        def install
            Dir.chdir(builddir) {
                Autobuild.progress "installing #{name}"
                Subprocess.run(self, 'install', Autobuild.tool(:make), "-j#{parallel_build_level}", 'install')
            }
            Autobuild.touch_stamp(installstamp)
            Autobuild.update_environment(prefix)
        end
    end
end

