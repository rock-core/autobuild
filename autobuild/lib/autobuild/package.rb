require 'autobuild/timestamps'
require 'autobuild/environment'
require 'autobuild/subcommand'

# Basic block for the autobuilder
#
# The build is done in three phases:
#   - import
#   - prepare
#   - build & install
class Autobuild::Package
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
    
    # The importer object for this package
    attr_accessor :import

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
    def installstamp; "#{prefix}/#{name}-#{STAMPFILE}" end

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
        raise ConfigException, "package #{name} is already defined" if Package[name]
        @@packages[name] = self

        # Call the config block (if any)
        yield(self) if block_given?
        
        # Declare the installation stampfile
        file installstamp
        task "#{name}-build" => installstamp
        task :build => "#{name}-build"

        # Add dependencies declared in spec
        depends_on *depends if depends

        # Define the import task
        task "#{name}-import" do import end
        task :import => "#{name}-import"

        # Define the prepare task
        task "#{name}-prepare" do prepare end
        task :prepare => "#{name}-prepare"

        task(name) do
            Rake::Task("#{name}-import").invoke
            Rake::Task("#{name}-prepare").invoke
            Rake::Task("#{name}-build").invoke
        end
        task :default => name
    end

    def import; @import.import(self) if @import end
    def prepare; end

    # This package depends on +packages+
    def depends_on(*packages)
        packages.each do |p|
            p = p.to_s
            next if p == name
            unless Package[p]
                raise ConfigException.new(name), "package #{p} not defined"
            end
            file installstamp => Package[p].installstamp
            @dependencies << p
        end
    end

    # Declare that this package provides +packages+
    def provides(*packages)
        packages.each do |p|
            p = p.to_s
            @@provides[p] = self 
            task p => name
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

