require 'autobuild/timestamps'
require 'autobuild/environment'
require 'autobuild/package'
require 'autobuild/subcommand'

class Autotools < Package
    factory :autotools, self

    attr_reader :builddir

    def buildstamp; 
        "#{builddir}/#{target}-#{STAMPFILE}"
    end

    def initialize(target, options)
        super(target, options)

        @builddir = (options[:builddir] || "build")
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
                $PROGRAMS["aclocal"] ||= "aclocal"
                $PROGRAMS["autoconf"] ||= "autoconf"
                $PROGRAMS["autoheader"] ||= "autoheader"
                $PROGRAMS["automake"] ||= "automake"

                begin
                    subcommand(target, "configure", $PROGRAMS["aclocal"]) if @options[:aclocal]
                    subcommand(target, "configure", $PROGRAMS["autoconf"]) if @options[:autoconf]
                    subcommand(target, "configure", $PROGRAMS["autoheader"]) if @options[:autoheader]
                    subcommand(target, "configure", $PROGRAMS["automake"]) if @options[:automake]
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
            command = "#{srcdir}/configure --no-create --prefix=#{prefix}"

            configureflags = @options[:configureflags].to_a.collect { |item|
                item.to_a.join("")
            }.join(" ")
            command += " #{configureflags}" if !configureflags.empty?
            
            begin
                subcommand(target, "configure", command)
            rescue SubcommandFailed => e
                raise BuildException.new(e), "failed to configure #{target}"
            end
        }
    end

    def build
        Dir.chdir(builddir) {
            begin
                subcommand(target, "build", "./config.status")
                $PROGRAMS["make"] ||= "make"
                subcommand(target, "build", $PROGRAMS["make"])
            rescue SubcommandFailed => e
                raise BuildException.new(e), "failed to build #{target}"
            end
        }
        touch_stamp(buildstamp)
    end

    def install
        Dir.chdir(builddir) {
            make = ($PROGRAMS["make"] or "make")
            begin
                subcommand(target, "install", "#{make} install")
            rescue SubcommandFailed => e
                raise BuildException.new(e), "failed to install #{builddir}"
            end
        }
        touch_stamp(installstamp)
    end
end


