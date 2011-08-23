require 'set'
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
        oldpath = environment[name]
        if !oldpath || !oldpath.include?(path)
            env_add(name, path)
            if name == 'RUBYLIB'
                $LOAD_PATH.unshift path
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

    def self.each_env_search_path(prefix, patterns)
        arch_names = self.arch_names
        arch_size  = self.arch_size
        
        seen = Set.new
        patterns.each do |base_path|
            paths = []
            if base_path =~ /ARCHSIZE/
                base_path = base_path.gsub('ARCHSIZE', arch_size.to_s)
            end
            if base_path =~ /ARCH/
                arch_names.each do |arch|
                    paths << base_path.gsub('ARCH', arch)
                end
            else
                paths << base_path
            end
            paths.each do |p|
                p = File.join(prefix, *p.split('/'))
                if !seen.include?(p) && File.directory?(p)
                    yield(p)
                    seen << p
                end
            end
        end
    end

    def self.arch_size
        if @arch_size
            return @arch_size
        end

        @arch_size =
            if RbConfig::CONFIG['host_cpu'] =~ /64/
                64
            else 32
            end
    end

    def self.arch_names
        if @arch_names
            return @arch_names
        end

        result = Set.new
        if File.file?('/usr/bin/dpkg-architecture')
            arch = `/usr/bin/dpkg-architecture`.split.grep(/DEB_BUILD_MULTIARCH/).first
            if arch
                result << arch.chomp.split('=').last
            end
        end
        @arch_names = result
    end

    # Updates the environment when a new prefix has been added
    def self.update_environment(newprefix)
        if File.directory?("#{newprefix}/bin")
            env_add_path('PATH', "#{newprefix}/bin")
        end

        pkg_config_search = ['lib/pkgconfig', 'lib/ARCH/pkgconfig', 'libARCHSIZE/pkgconfig']
        each_env_search_path(newprefix, pkg_config_search) do |path|
            env_add_path('PKG_CONFIG_PATH', path)
        end
        ld_library_search = ['lib', 'lib/ARCH', 'libARCHSIZE']
        each_env_search_path(newprefix, ld_library_search) do |path|
            if !Dir.glob(File.join(path, "lib*.so")).empty?
                env_add_path('LD_LIBRARY_PATH', path)
            end
        end

        # Validate the new rubylib path
        new_rubylib = "#{newprefix}/lib"
        if File.directory?(new_rubylib) && !File.directory?(File.join(new_rubylib, "ruby")) && !Dir["#{new_rubylib}/**/*.rb"].empty?
            env_add_path('RUBYLIB', new_rubylib)
        end

        require 'rbconfig'
        ruby_arch    = File.basename(Config::CONFIG['archdir'])
        candidates = %w{rubylibdir archdir sitelibdir sitearchdir vendorlibdir vendorarchdir}.
            map { |key| Config::CONFIG[key] }.
            map { |path| path.gsub(/.*lib(?:32|64)?\/(\w*ruby\/)/, '\\1') }.
            each do |subdir|
                if File.directory?("#{newprefix}/lib/#{subdir}")
                    env_add_path("RUBYLIB", "#{newprefix}/lib/#{subdir}")
                end
            end
    end
end

Autobuild.update_environment '/'
Autobuild.update_environment '/usr'
Autobuild.update_environment '/usr/local'
