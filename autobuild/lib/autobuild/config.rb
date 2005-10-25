require 'yaml'
require 'pathname'

require 'autobuild/config-interpolator'
require 'autobuild/reporting'
require 'autobuild/package'
require 'autobuild/importer'

class Hash
    def keys_to_sym
        inject(Hash.new) do |h, sample|
            k, v = sample[0], sample[1]
            if v.respond_to?(:keys_to_sym)
                h[k.to_sym] = v.keys_to_sym
            else
                h[k.to_sym] = v
            end
            h
        end
    end

    def each_recursive(&p)
        each { |k, v|
            yield(k, v)
            if v.respond_to?(:each_recursive)
                v.each_recursive(&p)
            end
        }
    end
end

module Config
    def self.check_backward_compatibility(config)
        if config.has_key?('autobuild-config')
            puts 'WARNING: the \'autobuild-config\' block is now named \'autobuild\''
        end
        config.each_recursive { |k, v|
            if k == 'common-config'
                puts 'WARNING: the \'common-config\' blocks are now named \'common\''
            end
        }
        if config["autobuild"] && config["autobuild"]["clean-log"]
            puts 'WARNING: the \'clean-log\' option is now named \'clean_log\''
        end
    end

    def self.load(conffile, user_options = Options.nil)
        case conffile
        when Hash
            config = conffile
        else
            data = YAML.load(conffile)
            config = Interpolator.interpolate(data)
        end

        check_backward_compatibility(config)
        config = config.keys_to_sym
        if !config[:autobuild]
            raise ConfigException, "no toplevel autobuild config block"
        end

        # Merge user_options into the autobuild block
        autobuild_config = config[:autobuild]
        default_options = Options.default
        user_options.each_pair { |sym, value|
            if !value.nil?
                autobuild_config[sym] = value
            elsif !autobuild_config.has_key?(sym)
                autobuild_config[sym] = default_options.send(sym)
            end
        }

        $VERBOSE = autobuild_config[:verbose]
        $trace = $DEBUG   = autobuild_config[:debug]

        get_autobuild_config(config)
        get_package_config(config)
    end

    def self.get_autobuild_config(config)
        $PROGRAMS = (config[:programs] or "make")
        
        autobuild = config[:autobuild]
        $SRCDIR = File.expand_path(autobuild[:srcdir], Dir.pwd)
        $PREFIX = File.expand_path(autobuild[:prefix], Dir.pwd)
        $LOGDIR = File.expand_path(autobuild[:logdir] || "autobuild", $PREFIX)

        FileUtils.mkdir_p $SRCDIR if !File.directory?($SRCDIR)
        FileUtils.mkdir_p $LOGDIR if !File.directory?($LOGDIR)
        if autobuild[:clean_log]
            puts "Cleaning log dir #{$LOGDIR}"
            FileUtils.rm_rf Dir.glob("#{$LOGDIR}/*.log")
        end

        if autobuild[:mail]
            mail_config = (autobuild[:mail].respond_to?(:[])) ? autobuild[:mail] : nil
            Reporting << MailReporter.new(mail_config)
        end
        $UPDATE = autobuild[:update]
        $NICE   = autobuild[:nice]

        autobuild[:environment].to_a.each { |k, v|
            ENV[k.to_s] = v.to_a.join(':')
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
        config[:srcdir] ||= name.to_s
        config[:prefix] ||= name.to_s

        # Initializes the package
        Package.build(package_type, name, config)
    end

    def self.get_package_config(config)
        packages = config[:packages]
        return if !packages
        
        # Get the common config block
        common = packages[:common]
        packages.each do |p, config|
            next if p == :common

            # Merge the common config
            config = config.merge(common) { |k, v1, v2|
                if v2.respond_to?(:to_ary)
                    v1.to_a | v2.to_ary
                elsif v2.respond_to?(:to_str)
                    v1.to_s + " " + v2.to_str
                end
            }
            # Remove p -> p dependency which may come from common
            if config.has_key?(:depends)
                config[:depends] = config[:depends].to_a.reject { |el| el == p.to_s }
            end

            add_package(p, config)
        end

        # Post-import, pre-build pass
        Package.each(false) { |name, pkg| pkg.prepare }
    end

    private_class_method :get_autobuild_config, :get_package_config, :add_package
end

