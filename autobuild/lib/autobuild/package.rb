require 'autobuild/timestamps'
require 'autobuild/environment'
require 'autobuild/subcommand'

class Autobuild::Package
    @@packages = {}
    @@provides = {}

    attr_reader     :target
    attr_accessor   :srcdir, :prefix

    ## The file which marks when the last sucessful install
    # has finished. The path is absolute
    #
    # A package is sucessfully built when it is installed
    def installstamp; "#{prefix}/#{target}-#{STAMPFILE}" end

    def initialize(target)
        target = target.to_s
        raise ConfigException, "package #{target} is already defined" if Package[target]

        # Declare the task in rake
        @target = target
        task target
        @@packages[target] = self
        
        @dependencies   = Array.new
        @provides       = Array.new

        # Read 'options'
        options = Hash.new if options.empty?
        @srcdir, @prefix = 
            (options[:srcdir] or target),
            (options[:prefix] or "")
        @import = options[:import]
        options[:depends_on].to_a.each { |p| depends_on(p) }
        options[:provides].to_a.each   { |p| provides(p) }

        # Call the config block (if any)
        yield(self) if block_given?
        
        @srcdir, @prefix =
            File.expand_path(@srcdir, Config.srcdir).freeze,
            File.expand_path(@prefix, Config.prefix).freeze

        file installstamp
        task target => installstamp
        @import.import(self) if @import
    end

    ## The importer object for this package
    def import=(importer); @import = importer end

    ## This package depends on +packages+
    def depends_on(*packages)
        packages.each do |p|
            p = p.to_s
            task target => p
            @dependencies << p
        end
    end

    ## Declare that this package provides +packages+
    def provides(*packages)
        packages.each do |p|
            p = p.to_s
            @@provides[p] = self 
            task p => target
            @provides << p
        end
    end




    def self.each(with_provides = false, &p)
        @@packages.each(&p) 
        @@provides.each(&p) if with_provides
    end
    def self.[](target)
        @@packages[target.to_s] or @@provides[target.to_s]
    end
end

