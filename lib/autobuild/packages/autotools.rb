require 'pathname'
require 'autobuild/timestamps'
require 'autobuild/environment'
require 'autobuild/package'
require 'autobuild/subcommand'
require 'shellwords'
require 'fileutils'

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
    class Autotools < Configurable
        attr_accessor   :using
        attr_accessor   :configureflags

        @builddir = 'build'
        
        def configurestamp; "#{builddir}/config.status" end

        def initialize(options)
            @using = Hash.new
	    @configureflags = []

            super
        end
        
        # Declare that the given target can be used to generate documentation
        def with_doc(target = 'doc')
            doc_task do
                Dir.chdir(builddir) do
                    progress "generating documentation for %s"
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
            programs =
                if programs.size == 1
                    programs.first
                else
                    programs
                end

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

        def prepare_for_forced_build
            autodetect_needed_stages
            if using[:autoconf]
                FileUtils.rm_f File.join(srcdir, 'configure')
            end

            if using[:automake]
                Find.find(srcdir) do |path|
                    if File.basename(path) == "Makefile.in"
                        FileUtils.rm_f path
                    end
                end
            end

            FileUtils.rm_f configurestamp
        end

        def prepare
            super

	    # Check if config.status has been generated with the
	    # same options than the ones in configureflags
            #
            # If it is not the case, remove it to force reconfiguration
	    configureflags.flatten!
	    force_reconfigure = false
	    if File.exists?(configurestamp)
		output = IO.popen("#{configurestamp} --version").readlines.grep(/with options/).first.chomp
		raise "invalid output of config.status --version" unless output =~ /with options "(.*)"$/
		options = Shellwords.shellwords($1)

		# Add the --prefix option to the configureflags array
		testflags = ["--prefix=#{prefix}"] + Array[*configureflags]
		old_opt = options.find   { |o| !testflags.include?(o) }
		new_opt = testflags.find { |o| !options.include?(o) }
		if old_opt || new_opt
		    FileUtils.rm_f configurestamp # to force reconfiguration
		end
	    end

            regen_target = create_regen_target
            file configurestamp => regen_target
        end

    private
        def autodetect_needed_stages
            # Autodetect autoconf/aclocal/automake
            #
            # Let the user disable the use of autoconf explicitely by using 'false'.
            # 'nil' means autodetection
            if using[:autoconf].nil?
                if File.file?(File.join(srcdir, 'configure.in')) || File.file?(File.join(srcdir, 'configure.ac'))
                    using[:autoconf] = true 
                end
            end
            using[:aclocal] = using[:autoconf] if using[:aclocal].nil?
            if using[:automake].nil?
                using[:automake] = File.exists?(File.join(srcdir, 'Makefile.am'))
            end

            if using[:libtool].nil?
                using[:libtool] = File.exists?(File.join(srcdir, 'ltmain.sh'))
            end
        end

        # Adds a target to rebuild the autotools environment
        def create_regen_target(confsource = nil)
	    conffile = "#{srcdir}/configure"
	    if confsource
		file conffile => confsource
	    elsif confext = %w{.ac .in}.find { |ext| File.exists?("#{conffile}#{ext}") }
		file conffile => "#{conffile}#{confext}"
	    else
		raise PackageException.new(name), "neither configure.ac nor configure.in present in #{srcdir}"
	    end

            file conffile do
                Dir.chdir(srcdir) do
                    if using[:autogen].nil?
                        using[:autogen] = %w{autogen autogen.sh}.find { |f| File.exists?(f) }
                    end

                    autodetect_needed_stages

                    progress "generating build system for %s"
                    if using[:libtool]
                        Subprocess.run(self, 'configure', Autobuild.tool('libtoolize'), '--copy')
                    end
                    if using[:autogen]
                        Subprocess.run(self, 'configure', File.expand_path(using[:autogen]))
                    else
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
            super do
                Dir.chdir(builddir) do
                    command = [ "#{srcdir}/configure", "--no-create", "--prefix=#{prefix}" ]
                    command += Array[*configureflags]
                    
                    progress "configuring build system for %s"
                    Subprocess.run(self, 'configure', *command)
                end
            end
        end

        # Do the build in builddir
        def build
            Dir.chdir(builddir) do
                progress "building %s"
                Subprocess.run(self, 'build', './config.status')
                Subprocess.run(self, 'build', Autobuild.tool(:make), "-j#{parallel_build_level}")
            end
            Autobuild.touch_stamp(buildstamp)
        end

        # Install the result in prefix
        def install
            Dir.chdir(builddir) do
                progress "installing %s"
                Subprocess.run(self, 'install', Autobuild.tool(:make), "-j#{parallel_build_level}", 'install')
            end

            super
        end
    end
end

