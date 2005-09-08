require 'autobuild/timestamps'
require 'autobuild/environment'
require 'autobuild/subcommand'

class Package
    @@packages = {}

    attr_reader :dependencies
    attr_reader :target, :srcdir, :prefix

    def installstamp; "#{prefix}/#{target}-#{STAMPFILE}" end
    def self.[](target); @@packages[target] end

    def initialize(target, options)
        @target = Package.name2target(target)
        raise ConfigException, "Package #{target} is already defined" if Package[target]
            
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
        @@packages[p] = self 
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

