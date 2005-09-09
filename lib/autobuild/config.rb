require 'yaml'
require 'pathname'

require 'autobuild/logging'
require 'autobuild/package'
require 'autobuild/importer'

class Regexp
    def each_match(string)
        string = string.to_str
        while data = match(string)
            yield(data)
            string = data.post_match
        end
    end
end

class UndefinedVariable < Exception
    attr_reader :name
    def initialize(name); @name = name end
end

class Interpolator
    VarDefKey = 'defines'
    InterpolationMatch = Regexp.new('\$\{([^}]+)\}|\$(\w+)')

    def self.interpolate(config, parent = nil)
        Interpolator.new(config, parent).interpolate
    end

    def initialize(node, parent = nil, variables = {})
        @node = node
        @variables = {}
        @defines = {}
        @parent = parent
    end

    def interpolate
        case @node
        when Hash
            @defines = (@node[VarDefKey] || {})

            interpolated = Hash.new
            @node.each do |k, v|
                next if k == VarDefKey
                interpolated[k] = Interpolator.interpolate(v, self)
            end

            interpolated

        when Array
            @node.collect { |v| Interpolator.interpolate(v, self) }

        else
            if @node.respond_to?(:to_str)
                do_string(@node.to_str) { |varname| value_of(varname) }
            else
                @node
            end
        end
    end

    def value_of(name)
        if @defines.has_key?(name)
            value = @defines.delete(name)
            @variables[name] = do_string(value) { |varname|
                begin
                    value_of(varname)
                rescue UndefinedVariable => e
                    if e.varname == name
                        raise "Cyclic reference found in definition of #{name}"
                    else
                        raise
                    end
                end
            }
        elsif @variables.has_key?(name)
            @variables[name]
        elsif @parent
            @parent.value_of(name)
        else
            raise UndefinedVariable.new(name), "Interpolated variable #{name} is not defined"
        end
    end

    def do_string(value)
        return value if value.empty?

        interpolated = ''
        data = nil
        InterpolationMatch.each_match(value) do |data|
            varname = data[1] || data[2]
            interpolated << data.pre_match << yield(varname)
        end
        return data ? (interpolated << data.post_match) : value
    end
end

module Config
    def self.load(conffile, user_options)
        data = YAML.load( File.open(conffile) )
        data = Interpolator.interpolate(data)

        get_autobuild_config(data, user_options)
        get_package_config(data)
    rescue ConfigException => error
        error(error, "Error in config file '#{conffile}'")
        exit(1)
    rescue ImportException => error
        error(error, "Error: unable to import #{p}")
        exit(1)
    end

    def self.get_autobuild_config(data, options)
        $PROGRAMS = (data["programs"] or "make")
        
        setup = data["autobuild-config"]
        raise ConfigException, "no autobuild-config block" if !setup
            
        $SRCDIR = (options.srcdir or setup["srcdir"])
        $PREFIX = (options.prefix or setup["prefix"])
        if !$SRCDIR || !$PREFIX
            raise ConfigException, "you must at least set srcdir and prefix in the config files"
        end

        $LOGDIR = (options.logdir or setup["logdir"] or "#{$PREFIX}/autobuild")

        FileUtils.mkdir_p $SRCDIR if !File.directory?($SRCDIR)
        FileUtils.mkdir_p $LOGDIR if !File.directory?($LOGDIR)
        if setup["clean-log"]
            puts "Cleaning log dir #{$LOGDIR}"
            FileUtils.rm_rf Dir.glob("#{$LOGDIR}/*")
        end

        $MAIL = setup["mail"]
        $NOUPDATE = (options.noupdate or setup["noupdate"] or false)

        envvars = setup["environment"]
        envvars.each { |k, v|
            ENV[k] = v.to_a.join(":")
        }
    end

    def self.add_package(name, config)
        # Get the package type
        package_type = config[:type].to_sym
        require "autobuild/packages/#{package_type}"

        # Build the importer object, if there is one
        import_type = config[:import]
        if import_type
            require "autobuild/import/#{import_type}"
            if !config.has_key?(:source)
                raise ConfigException, "missing 'source' option in the '#{name}' package description"
            end

            config[:import] = Import.method(import_type).call(config[:source], config)
        end

        # Set the default dir if needed
        config[:srcdir] ||= name
        config[:prefix] ||= name

        # Build the rake rules for this package
        Package.build(package_type, name, config)
    end

    # Get the package config
    def self.get_package_config(data)
        setup = data["packages"]
        
        # Get the common config block
        common_config = Hash.new
        setup["common-config"].each { |k, v| common_config[k.to_sym] = v } if setup.has_key?("common-config")

        setup.each do |p, yml_config|
            next if p == "common-config"

            # Change keys into symbols
            config = {}
            yml_config.each do |k, v|
                config[k.to_sym] = v
            end

            # Merge the common config
            config = config.merge(common_config) { |k, v1, v2|
                if v2.respond_to?(:to_ary)
                    v1.to_a | v2.to_ary
                elsif v2.respond_to?(:to_str)
                    v1.to_s + " " + v2.to_str
                end
            }
            # Remove p -> p dependency which may come from common_config
            if config.has_key?(:depends)
                config[:depends] = config[:depends].to_a.reject { |el| el == p }
            end

            add_package(p, config)
        end
    end

    private_class_method :get_autobuild_config, :get_package_config, :add_package
end

