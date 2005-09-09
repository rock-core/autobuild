require 'autobuild/timestamps'
require 'autobuild/environment'
require 'autobuild/package'
require 'autobuild/subcommand'

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
        raise ConfigException, "Autotools packages need a non-empty builddir" if (@builddir.nil? || @builddir.empty?)
        raise ConfigException, "No support for absolute builddirs" if (Pathname.new(@builddir).absolute?)
        @builddir = File.expand_path(builddir, srcdir)

        regen_targets

        file "#{builddir}/config.status" => "#{srcdir}/configure" do
            configure
        end

        source_tree srcdir, builddir
        file srcdir => dependencies if !dependencies.empty?
        file buildstamp => [ srcdir, "#{builddir}/config.status" ] do 
            build
        end
        file installstamp => [ buildstamp ] do 
            install
            update_environment(prefix)
        end
        update_environment(prefix)
    end

    def regen_targets
        conffile = "#{srcdir}/configure"
        if File.exists?("#{conffile}.ac")
            file conffile => [ "#{conffile}.ac" ]
        else
            file conffile => [ "#{conffile}.in" ]
        end
        file conffile do
            Dir.chdir(srcdir) {
                $PROGRAMS['aclocal']     ||= 'aclocal'
                $PROGRAMS['autoconf']    ||= 'autoconf'
                $PROGRAMS['autoheader']  ||= 'autoheader'
                $PROGRAMS['automake']    ||= 'automake'

                begin
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

                    subcommand(target, 'configure', $PROGRAMS['aclocal'])    if @options[:aclocal]
                    subcommand(target, 'configure', $PROGRAMS['autoconf'])   if @options[:autoconf]
                    subcommand(target, 'configure', $PROGRAMS['autoheader']) if @options[:autoheader]
                    subcommand(target, 'configure', $PROGRAMS['automake'])   if @options[:automake]
                rescue SubcommandFailed => e
                    raise BuildException.new(e), "failed to build the configure environment of #{target}"
                end
            }
        end
    end

    def configure
        if File.exists?(builddir) && !File.directory?(builddir)
            raise BuildException, "#{builddir} already exists but is not a directory"
        end

        FileUtils.mkdir_p builddir if !File.directory?(builddir)
        Dir.chdir(builddir) {
            command = [ "#{srcdir}/configure", "--no-create", "--prefix=#{prefix}" ]
            command |= @options[:configureflags].to_a
            
            begin
                subcommand(target, 'configure', *command)
            rescue SubcommandFailed => e
                raise BuildException.new(e), "failed to configure #{target}"
            end
        }
    end

    def build
        Dir.chdir(builddir) {
            begin
                subcommand(target, 'build', './config.status')
                $PROGRAMS['make'] ||= 'make'
                subcommand(target, 'build', $PROGRAMS['make'])
            rescue SubcommandFailed => e
                raise BuildException.new(e), "failed to build #{target}"
            end
        }
        touch_stamp(buildstamp)
    end

    def install
        Dir.chdir(builddir) {
            make = ($PROGRAMS['make'] or 'make')
            begin
                subcommand(target, 'install', make, 'install')
            rescue SubcommandFailed => e
                raise BuildException.new(e), "failed to install #{builddir}"
            end
        }
        touch_stamp(installstamp)
    end
end


