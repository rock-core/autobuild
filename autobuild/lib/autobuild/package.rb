require 'autobuild/timestamps'
require 'autobuild/environment'
require 'autobuild/subcommand'

class Autobuild::Package
    @@packages = {}
    @@provides = {}

    attr_reader :target
    attr_accessor :srcdir, :prefix

    ## The file which marks when the last sucessful install
    # has finished. The path is absolute
    #
    # A package is sucessfully built when it is installed
    def installstamp; "#{prefix}/#{target}-#{STAMPFILE}" end

    def self.each(with_provides = false, &p)
        @@packages.each(&p) 
        @@provides.each(&p) if with_provides
    end
    def self.[](target)
        @@packages[target] or @@provides[target]
    end

    ## Available options
    #  * +:srcdir   - the source dir (default: package name). If a relative path, it is based on Autobuild::Config.srcdir
    #  * +:prefix   - the install dir (default: empty). If a relative path, it is based on Autobuild::Config.prefix
    #  * +:import   - the package importer object
    #  * +:depends  - the list of package name we depend upon
    #  * +:provides - a list of aliases for this package
    #
    #  Alternatively, a block can be given to 
    #  The import is done after t
    #
    def initialize(target, *options)
        @target = target
        raise ConfigException, "package #{target} is already defined" if Package[target]
        options = Hash.new if options.empty?
            
        @dependencies   = Array.new
        @provides       = Array.new

        @srcdir, @prefix = 
            (options[:srcdir] or target.to_s),
            (options[:prefix] or "")

        @import = options[:import]

        options[:depends_on].to_a.each { |p| depends_on(p) }
        options[:provides].to_a.each   { |p| provides(p) }

        yield(self) if block_given?
        
        @@packages[target] = self
        @srcdir, @prefix =
            File.expand_path(@srcdir, Config.srcdir),
            File.expand_path(@prefix, Config.prefix)
        @srcdir = @srcdir.freeze!
        @prefix = @prefix.freeze!

        file installstamp
        task @target => installstamp
        @import.import(self) if @import
    end


    def import=(importer); @import = importer end
    def depends_on(*packages)
        packages.each do |p|
            p = Package.to_target(p)
            task target => p
            @dependencies << p
        end
    end

    def provides(*packages)
        packages.each do |p|
            p = Package.to_target(p)
            @@provides[p] = self 
            task p => target
            @provides << p
        end
    end

    def self.all; @@packages; end
    def self.to_target(*packages)
        packages = packages.collect do |name|
            if name.respond_to?(:id2name)
                name.id2name
            else
                raise TypeError, "#{name.class} does not respond to id2name"
            end
        end

        return packages.first if packages.size == 1
        return packages
    end

    @@factories = Hash.new
    def self.factory(type, klass)
        @@factories[type] = klass
    end
    def self.build(type, name, options)
        raise ConfigException, "#{type} is not a valide package type" if !@@factories.has_key?(type)

        target = Package.to_target(name)
        task :default => [ target ]
        raise ConfigException, "there is already a package named #{target}" if Package[target]
        return @@factories[type].new(target, options)
    end
end

