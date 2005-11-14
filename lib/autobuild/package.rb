require 'autobuild/timestamps'
require 'autobuild/environment'
require 'autobuild/subcommand'

class Autobuild::Package
    @@packages = {}
    @@provides = {}

    attr_reader :dependencies
    attr_reader :target, :srcdir, :prefix

    def installstamp; "#{prefix}/#{target}-#{STAMPFILE}" end

    def self.each(with_provides = false, &p)
        @@packages.each(&p) 
        @@provides.each(&p) if with_provides
    end
    def self.[](target)
        @@packages[target] or @@provides[target]
    end

    ## Available options
    #   srcdir: the source dir. If a relative path, it is based on $SRCDIR
    #   prefix: the install dir. If a relative path, it is based on $PREFIX
    #   import: the package importer object
    #   depends: the list of package name we depend upon
    #   provides: a list of aliases for this package
    #
    # $SRCDIR and $PREFIX are supposed to be valid absolute paths
    def initialize(target, options)
        @target = Package.name2target(target)
        raise ConfigException, "package #{target} is already defined" if Package[target]
            
        @options = options
        @dependencies = Array.new
        @provides = Array.new

        srcdir, prefix = 
            (options[:srcdir] or target.to_s),
            (options[:prefix] or "")

        srcdir = File.expand_path(srcdir, $SRCDIR)
        prefix = File.expand_path(prefix, $PREFIX)

        @srcdir, @prefix = srcdir, prefix
        @import = options[:import]
        @import.import(self) if @import

        file installstamp
        task @target => installstamp

        @options[:depends].to_a.each { |p| depends_on(p) }
        @options[:provides].to_a.each { |p| provides(p) }
        @@packages[target] = self
    end

    @@factories = Hash.new

    def depends_on(p)
        p = Package.name2target(p)
        task target => p
        puts "#{target} depends on #{p}"

        @dependencies << p
    end

    def provides(p)
        p = Package.name2target(p)
        @@provides[p] = self 
        puts "Defining #{p} as an alias to #{target}"
        task p => target

        @provides << p
    end

    def self.all; @@packages; end
    def self.name2target(name)
        if name.respond_to?(:to_str)
            name.to_str.gsub(/-\//, '_').to_sym
        elsif name.respond_to?(:to_sym)
            name.to_sym
        else
            raise TypeError, "expected either a symbol or a string, got #{name.class}"
        end
    end
    def self.factory(type, klass)
        @@factories[type] = klass
    end
    def self.build(type, name, options)
        raise ConfigException, "#{type} is not a valide package type" if !@@factories.has_key?(type)

        target = name2target(name)
        task :default => [ target ]
        raise ConfigException, "there is already a package named #{target}" if Package[target]
        return @@factories[type].new(target, options)
    end
end

