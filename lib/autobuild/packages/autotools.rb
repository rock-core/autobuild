require 'autobuild/timestamps'
require 'autobuild/environment'
require 'autobuild/package'
require 'autobuild/subcommand'

module Autobuild
    ## 
    # ==== Handles autotools-based packages
    #
    # == Used programs
    # - aclocal, autoheader, autoconf, automake
    #
    # == Available options
    # - aclocal (default: true if autoconf is enabled, false otherwise) run aclocal
    # - autoconf (default: autodetect) run autoconf. Will be enabled if there is 
    #   +configure.in+ or +configure.ac+ in the source directory
    # - autoheader (default: false) run autoheader
    # - automake (default: autodetect) run automake. Will run automake if there is a 
    #   +Makefile.am+ in the source directory
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

        def buildstamp
            "#{builddir}/#{target}-#{STAMPFILE}"
        end

        def initialize(target, options)
            options = DefaultOptions.merge(options) { |key, old, new|
                (new.nil? || (new.respond_to?(:empty) && new.empty?)) ? old : new
            }
            super(target, options)

            @builddir = options[:builddir]
            raise ConfigException, "autotools packages need a non-empty builddir" if (@builddir.nil? || @builddir.empty?)
            raise ConfigException, "absolute builddirs are unsupported" if (Pathname.new(@builddir).absolute?)
            @builddir = File.expand_path(builddir, srcdir)
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

            if !dependencies.empty?
                file buildstamp => dependencies
                file srcdir => dependencies
            end

            file installstamp => buildstamp do 
                install
                Autobuild.update_environment(prefix)
            end
            Autobuild.update_environment(prefix)
        end

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
                    $PROGRAMS[:aclocal]     ||= 'aclocal'
                    $PROGRAMS[:autoconf]    ||= 'autoconf'
                    $PROGRAMS[:autoheader]  ||= 'autoheader'
                    $PROGRAMS[:automake]    ||= 'automake'

                    if @options[:autogen]
                        Subprocess.run(target, 'configure', File.expand_path(@options[:autogen]))
                    else
                        # Autodetect autoconf/aclocal/automake
                        if @options[:autoconf].nil?
                            @options[:autoconf] = 
                                File.exists?(File.join(srcdir, 'configure.in')) ||
                                File.exists?(File.join(srcdir, 'configure.ac'))
                        end
                        @options[:aclocal] ||= @options[:autoconf]
                        if @options[:automake].nil?
                            @options[:automake] = File.exists?(File.join(srcdir, 'Makefile.am'))
                        end

                        Subprocess.run(target, 'configure', $PROGRAMS[:aclocal])    if @options[:aclocal]
                        Subprocess.run(target, 'configure', $PROGRAMS[:autoconf])   if @options[:autoconf]
                        Subprocess.run(target, 'configure', $PROGRAMS[:autoheader]) if @options[:autoheader]
                        Subprocess.run(target, 'configure', $PROGRAMS[:automake])   if @options[:automake]
                    end
                }
            end
        end

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

        def build
            Dir.chdir(builddir) {
                Subprocess.run(target, 'build', './config.status')
                $PROGRAMS['make'] ||= 'make'
                Subprocess.run(target, 'build', $PROGRAMS['make'])
            }
            touch_stamp(buildstamp)
        end

        def install
            Dir.chdir(builddir) {
                make = ($PROGRAMS['make'] or 'make')
                Subprocess.run(target, 'install', make, 'install')
            }
            touch_stamp(installstamp)
        end
    end
end

