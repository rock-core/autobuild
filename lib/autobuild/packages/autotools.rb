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
    # * aclocal
    # * autoheader
    # * autoconf
    # * automake
    #
    # == Available options
    # * aclocal     (default: true if autoconf is enabled, false otherwise) run aclocal
    # * autoconf    (default: true)
    # * autoheader  (default: false) run autoheader
    # * automake    (default: autodetect) run automake. Will run automake if there is a 
    #               +Makefile.am+ in the source directory
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
        def buildstamp; "#{builddir}/#{name}-#{STAMPFILE}" end

        def initialize(options)
            @using = Hash.new
	    @configureflags = []

            super

            Autobuild.update_environment(prefix)
        end

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
            #file "#{builddir}/config.status" => stamps
            file buildstamp => stamps
        end

        def ensure_dependencies_installed
            dependencies.each do |pkg|
                Rake::Task[Package[pkg].installstamp].invoke
            end
        end

        def prepare
	    # Check if config.status has been generated with the
	    # same options than the ones in configureflags
	    config_status = "#{builddir}/config.status"

	    force_reconfigure = false
	    if File.exists?(config_status)
		output = IO.popen("#{config_status} --version").readlines.grep(/with options/).first.chomp
		raise "invalid output of config.status --version" unless output =~ /with options "(.*)"$/
		options = Shellwords.shellwords($1)

		# Add the --prefix option to the configureflags array
		testflags = ["--prefix=#{prefix}"] + configureflags
		old_opt = options.find { |o| !testflags.include?(o) }
		new_opt = testflags.find { |o| !options.include?(o) }
		if old_opt || new_opt
		    File.rm_f config_status # to force reconfiguration
		end
	    end

            file config_status => regen do
                ensure_dependencies_installed
                configure
            end

            source_tree srcdir, /^#{Regexp.quote(builddir)}/
            file buildstamp => [ srcdir, "#{builddir}/config.status" ] do 
                ensure_dependencies_installed
                build
            end

            file installstamp => buildstamp do 
                install
                Autobuild.update_environment(prefix)
            end
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

                    if using[:autogen]
                        Subprocess.run(name, 'configure', File.expand_path(using[:autogen]))
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

                                Subprocess.run(name, 'configure', tool_program)
                            end
                        end
                    end
                }
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
                command |= Array[*configureflags]
                
                Subprocess.run(name, 'configure', *command)
            }
        end

        # Do the build in builddir
        def build
            Dir.chdir(builddir) {
                Subprocess.run(name, 'build', './config.status')
                Subprocess.run(name, 'build', Autobuild.tool(:make))
            }
            touch_stamp(buildstamp)
        end

        # Install the result in prefix
        def install
            Dir.chdir(builddir) {
                Subprocess.run(name, 'install', Autobuild.tool(:make), 'install')
            }
            touch_stamp(installstamp)
        end
    end
end

