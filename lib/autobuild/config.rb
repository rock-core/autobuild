require 'yaml'
require 'pathname'

require 'autobuild/logging'
require 'autobuild/package'
require 'autobuild/importer'

module Config
    def self.load(conffile, user_options)
        data = YAML.load( File.open(conffile) )

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
            ENV[k] = ( v.to_a.collect { |path| path.to_a.join("") }.join(":") )
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
                config[:depends] = config[:depends].to_a.find_all { |el| el != p }
            end

            add_package(p, config)
        end
    end

    private_class_method :get_autobuild_config, :get_package_config, :add_package
end

