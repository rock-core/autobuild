module Autobuild
    @environment = Hash.new
    class << self
        attr_reader :environment
    end

    # Set a new environment variable
    def self.env_set(name, *values)
        environment.delete(name)
        env_add(name, *values)
    end
    # Adds a new value to an environment variable
    def self.env_add(name, *values)
        set = environment[name]
        if !set
            set = Array.new
        elsif !set.respond_to?(:to_ary)
            set = [set]
        end

        values.concat(set)
        @environment[name] = values
        ENV[name] = values.join(":")
    end

    def self.env_add_path(name, path, *paths)
        if File.directory?(path)
            oldpath = environment[name]
            if !oldpath || !oldpath.include?(path)
                env_add(name, path)
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

        # Validate the new rubylib path
        new_rubylib = "#{newprefix}/lib"
        if !File.directory?(File.join(new_rubylib, "ruby")) && !Dir["#{new_rubylib}/**/*.rb"].empty?
            env_add_path('RUBYLIB', new_rubylib)
        end

        require 'rbconfig'
        ruby_arch = File.basename(Config::CONFIG['archdir'])
        env_add_path("RUBYLIB", "#{newprefix}/lib/ruby/1.8")
        env_add_path("RUBYLIB", "#{newprefix}/lib/ruby/1.8/#{ruby_arch}")
    end
end

