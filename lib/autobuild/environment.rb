module Autobuild
    @inherited_environment = Hash.new
    @environment = Hash.new
    class << self
        attr_reader :inherited_environment
        attr_reader :environment
    end

    def self.env_clear(name)
        environment[name] = nil
        inherited_environment[name] = nil
    end

    # Set a new environment variable
    def self.env_set(name, *values)
        env_clear(name)
        env_add(name, *values)
    end
    # Adds a new value to an environment variable
    def self.env_add(name, *values)
        set = if environment.has_key?(name)
                  environment[name]
              end

        if !inherited_environment.has_key?(name)
            if parent_env = ENV[name]
                inherited_environment[name] = parent_env.split(':')
            else
                inherited_environment[name] = Array.new
            end
        end

        if !set
            set = Array.new
        elsif !set.respond_to?(:to_ary)
            set = [set]
        end

        values.concat(set)
        @environment[name] = values

        inherited = inherited_environment[name] || Array.new
        ENV[name] = (values + inherited).join(":")
    end

    def self.env_add_path(name, path, *paths)
        if File.directory?(path)
            oldpath = environment[name]
            if !oldpath || !oldpath.include?(path)
                env_add(name, path)
                if name == 'RUBYLIB'
                    $LOAD_PATH.unshift path
                end
            end
        end
        if !paths.empty?
            env_add_path(name, *paths)
        end
    end

    # DEPRECATED: use env_add_path instead
    def self.pathvar(path, varname)
        if File.directory?(path)
            if block_given?
                return unless yield(path)
            end
            env_add_path(varname, path)
        end
    end

    # Updates the environment when a new prefix has been added
    def self.update_environment(newprefix)
        env_add_path('PATH', "#{newprefix}/bin")
        env_add_path('PKG_CONFIG_PATH', "#{newprefix}/lib/pkgconfig")
        if File.directory?("#{newprefix}/lib") && !Dir.glob("#{newprefix}/lib/*.so").empty?
            env_add_path('LD_LIBRARY_PATH', "#{newprefix}/lib")
        end

        # Validate the new rubylib path
        new_rubylib = "#{newprefix}/lib"
        if !File.directory?(File.join(new_rubylib, "ruby")) && !Dir["#{new_rubylib}/**/*.rb"].empty?
            env_add_path('RUBYLIB', new_rubylib)
        end

        require 'rbconfig'
        ruby_arch    = File.basename(Config::CONFIG['archdir'])
        candidates = %w{rubylibdir archdir sitelibdir sitearchdir vendorlibdir vendorarchdir}.
            map { |key| Config::CONFIG[key] }.
            map { |path| path.gsub(/.*lib(?:32|64)?\/(\w*ruby\/)/, '\\1') }.
            each { |subdir| env_add_path("RUBYLIB", "#{newprefix}/lib/#{subdir}") }
    end
end

