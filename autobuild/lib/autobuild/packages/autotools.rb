require 'autobuild/timestamps'
require 'autobuild/environment'
require 'autobuild/package'
require 'autobuild/subcommand'

module Autobuild
    ## 
    # ==== Handles autotools-based packages
    #
    # == Used programs (see <tt>Config.programs</tt>)
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
        factory :autotools, self

        attr_reader :builddir

        DefaultOptions = {
            :autoheader => false,
            :aclocal => nil,
            :autoconf => nil,
            :automake => nil,
            :builddir => 'build'
        }

        ## Build stamp
        # This returns the name of the file which marks when the package has been
        # successfully built for the last time. The path is absolute
        def buildstamp; "#{builddir}/#{target}-#{STAMPFILE}" end

        ##
        # Available options:
        # * +:builddir+ -   the subdir in which the package should be built 
        #                   before it is installed. It should be relative to 
        #                   the source dir. Default: 'build'
        # 
        # For other options, see the documentation of +Package::new+
        # 
        def initialize(target, options, &proc)
            options = DefaultOptions.merge(options) { |key, old, new|
                (new.nil? || (new.respond_to?(:empty) && new.empty?)) ? old : new
            }
            @builddir = options[:builddir]

            super(target, options, &proc)

            raise ConfigException, "autotools packages need a non-empty builddir" if (@builddir.nil? || @builddir.empty?)
            raise ConfigException, "absolute builddirs are unsupported" if (Pathname.new(@builddir).absolute?)
            @builddir = File.expand_path(@builddir, srcdir)
            Autobuild.update_environment(prefix)
        end

        def depends_on(*packages)
            super
            packages = Package.to_target(packages)
            file "#{builddir}/config.status" => packages
            file buildstamp => packages
        end

        def prepare
            regen_targets

            file "#{builddir}/config.status" => "#{srcdir}/configure" do
                configure
            end

            source_tree srcdir, builddir
            file buildstamp => [ srcdir, "#{builddir}/config.status" ] do 
                build
            end

            file installstamp => buildstamp do 
                install
                Autobuild.update_environment(prefix)
            end
        end


    private

        ## Adds a target to rebuild the autotools environment
        def regen_targets
            conffile = "#{srcdir}/configure"
            if File.exists?("#{conffile}.ac")
                file conffile => [ "#{conffile}.ac" ]
            elsif File.exists?("#{conffile}.in")
                file conffile => [ "#{conffile}.in" ]
            else
                raise PackageException.new(target), "neither configure.ac nor configure.in present in #{srcdir}"
            end
            file conffile do
                Dir.chdir(srcdir) {
                    if @options[:autogen]
                        Subprocess.run(target, 'configure', File.expand_path(@options[:autogen]))
                    else
                        # Autodetect autoconf/aclocal/automake
                        #
                        # Let the user disable the use of autoconf explicitely
                        @options[:autoconf] = true if @options[:autoconf].nil?
                        @options[:aclocal] = @options[:autoconf] if @options[:aclocal].nil?
                        if @options[:automake].nil?
                            @options[:automake] = File.exists?(File.join(srcdir, 'Makefile.am'))
                        end

                        [ :aclocal, :autoconf, :autoheader, :automake ].each do |tool|
                            if options[tool]
                                Subprocess.run(target, 'configure', Config.tool(tool))
                            end
                        end
                    end
                }
            end
        end

        ## Configure the builddir directory before starting make
        def configure
            if File.exists?(builddir) && !File.directory?(builddir)
                raise ConfigException, "#{builddir} already exists but is not a directory"
            end

            FileUtils.mkdir_p builddir if !File.directory?(builddir)
            Dir.chdir(builddir) {
                command = [ "#{srcdir}/configure", "--no-create", "--prefix=#{prefix}" ]
                command |= @options[:configureflags].to_a
                
                Subprocess.run(target, 'configure', *command)
            }
        end

        ## Do the build in builddir
        def build
            Dir.chdir(builddir) {
                Subprocess.run(target, 'build', './config.status')
                Subprocess.run(target, 'build', Config.tool(:make))
            }
            touch_stamp(buildstamp)
        end

        ## Install the result in prefix
        def install
            Dir.chdir(builddir) {
                Subprocess.run(target, 'install', Config.tool(:make), 'install')
            }
            touch_stamp(installstamp)
        end
    end
end

