require 'set'
require 'rbconfig'
require 'utilrb/hash/map_value'

module Autobuild
    @windows = RbConfig::CONFIG["host_os"] =~%r!(msdos|mswin|djgpp|mingw|[Ww]indows)!
    def self.windows?
        @windows
    end

    @macos =  RbConfig::CONFIG["host_os"] =~%r!([Dd]arwin)!
    def self.macos?
        @macos
    end

    @freebsd = RbConfig::CONFIG["host_os"].include?('freebsd') 
    def self.freebsd?
        @freebsd
    end

    def self.bsd?
        @freebsd || @macos #can be extended to some other OSes liek NetBSD
    end

    @msys =  RbConfig::CONFIG["host_os"] =~%r!(msys)!
    def self.msys?
        @msys
    end

    SHELL_VAR_EXPANSION =
        if windows? then "%%%s%%"
        else "$%s"
        end
    SHELL_SET_COMMAND =
        if windows? then "set %s=%s"
        else "%s=\"%s\""
        end
    SHELL_CONDITIONAL_SET_COMMAND =
        if windows? then "set %s=%s"
        else "if test -z \"$%1$s\"; then\n  %1$s=\"%3$s\"\nelse\n  %1$s=\"%2$s\"\nfi"
        end
    SHELL_UNSET_COMMAND =
        if windows? then "unset %s"
        else "unset %s"
        end
    SHELL_EXPORT_COMMAND =
        if windows? then "set %s"
        else "export %s"
        end
    SHELL_SOURCE_SCRIPT =
        if windows? then "%s"
        else ". \"%s\""
        end

    LIBRARY_PATH =
        if macos? then 'DYLD_LIBRARY_PATH'
        elsif windows? then 'PATH'
        else 'LD_LIBRARY_PATH'
        end

    LIBRARY_SUFFIX =
        if macos? then 'dylib'
        elsif windows? then 'dll'
        else 'so'
        end

    ORIGINAL_ENV = Hash.new
    ENV.each do |k, v|
        ORIGINAL_ENV[k] = v
    end

    # Manager class for environment variables
    class Environment
        # In generated environment update shell files, indicates whether an
        # environment variable should be overriden by the shell script, or
        # simply updated
        #
        # If inherited_environment[varname] is true, the generated shell script
        # will contain
        #   
        #   export VARNAME=new_value:new_value:$VARNAME
        #
        # otherwise
        #
        #   export VARNAME=new_value:new_value
        attr_reader :inherited_environment
        # List of the environment that should be set before calling a subcommand
        #
        # It is a map from environment variable name to the corresponding value.
        # If the value is an array, it is joined using the operating system's
        # path separator (File::PATH_SEPARATOR)
        attr_reader :environment
        attr_reader :source_after
        attr_reader :source_before

        attr_reader :inherited_variables

        attr_reader :resolved_env
        attr_reader :system_env
        attr_reader :original_env

        def initialize
            @inherited_environment = Hash.new
            @environment = Hash.new
            @source_before = Set.new
            @source_after = Set.new
            @inherit = true
            @inherited_variables = Set.new

            @system_env = Hash.new
            @original_env = ORIGINAL_ENV.dup
            @resolved_env = Hash.new
            ENV.each do |k, v|
                resolved_env[k] = v
            end
        end

        def initialize_copy(old)
            super
            @inherited_environment = @inherited_environment.
                map_value { |k, v| v.dup }
            @environment = @environment.
                map_value { |k, v| v.dup }
            @source_before = @source_before.dup
            @source_after = @source_after.dup
            @inherited_variables = @inherited_variables.dup

            @system_env = @system_env.
                map_value { |k, v| v.dup }
            @original_env = @original_env.
                map_value { |k, v| v.dup }
            @resolved_env = @resolved_env.
                map_value { |k, v| v.dup }
        end

        def [](name)
            resolved_env[name]
        end

        # Resets the value of +name+ to its original value. If it is inherited from
        # the 
        def reset(name = nil)
            if name
                environment.delete(name)
                inherited_environment.delete(name)
                init_from_env(name)
            else
                environment.keys.each do |env_key|
                    reset(env_key)
                end
            end
        end

        # Unsets any value on the environment variable +name+, including inherited
        # value.
        #
        # In a bourne shell, this would be equivalent to doing
        #   
        #   unset name
        #
        def clear(name = nil)
            if name
                environment[name] = nil
                inherited_environment[name] = nil
                update_var(name)
            else
                environment.keys.each do |env_key|
                    clear(env_key)
                end
            end
        end

        # Set a new environment variable
        def set(name, *values)
            environment.delete(name)
            add(name, *values)
        end


        # Returns true if the given environment variable must not be reset by the
        # env.sh script, but that new values should simply be prepended to it.
        #
        # @param [String,nil] name the environment variable that we want to check
        #   for inheritance. If nil, the global setting is returned.
        #
        # @see env_inherit env_inherit=
        def inherit?(name = nil)
            if @inherit
                if name 
                    @inherited_variables.include?(name)
                else true
                end
            end
        end

        # If true (the default), the environment variables that are marked as
        # inherited will be inherited from the global environment (during the
        # build as well as in the generated env.sh files)
        #
        # Otherwise, only the environment that is explicitely set in autobuild
        # will be passed on to subcommands, and saved in the environment
        # scripts.
        #
        # @see inherit? inherit
        def inherit=(value)
            @inherit = value
            inherited_environment.keys.each do |env_name|
                init_from_env(env_name)
            end
        end

        # Declare that the given environment variable must not be reset by the
        # env.sh script, but that new values should simply be prepended to it.
        #
        # @return [Boolean] true if environment inheritance is globally enabled and
        #   false otherwise. This is controlled by {env_inherit=}
        #
        # @see env_inherit? env_inherit=
        def inherit(*names)
            flag =
                if !names.last.respond_to?(:to_str)
                    names.pop
                else true
                end
            
            if flag
                @inherited_variables |= names
                names.each do |env_name|
                    init_from_env(env_name)
                end
            else
                names.each do |n|
                    if @inherited_variables.include?(n)
                        @inherited_variables.delete(n)
                        init_from_env(n)
                    end
                end
            end

            @inherit
        end

        def init_from_env(name)
            if inherit?(name) && (parent_env = original_env[name])
                inherited_environment[name] = parent_env.split(File::PATH_SEPARATOR)
            else
                inherited_environment[name] = Array.new
            end
            update_var(name)
        end

        def push(name, *values)
            if current = environment[name]
                current = current.dup
                env_set(name, *values)
                env_add(name, *current)
            else
                env_add(name, *values)
            end
        end

        # Adds a new value to an environment variable
        def add(name, *values)
            values = values.map { |v| expand(v) }

            set = if environment.has_key?(name)
                      environment[name]
                  end

            if !inherited_environment.has_key?(name)
                init_from_env(name)
            end

            if !set
                set = Array.new
            elsif !set.respond_to?(:to_ary)
                set = [set]
            end

            values.concat(set)
            @environment[name] = values
            update_var(name)
        end

        # Returns an environment variable value
        #
        # @param [String] name the environment variable name
        # @option options [Symbol] inheritance_mode (:expand) controls how
        #   environment variable inheritance should be done. If :expand, the current
        #   envvar value is inserted in the generated value. If :keep, the name of
        #   the envvar is inserted (as e.g. $NAME). If :ignore, inheritance is
        #   disabled in the generated value. Not that this applies only for the
        #   environment variables for which inheritance has been enabled with
        #   {#inherit}, other variables always behave as if :ignore was selected.
        # @return [nil,Array<String>] either nil if this environment variable is not
        #   set, or an array of values. How the values should be joined to form the
        #   actual value is OS-specific, and not handled by this method
        def value(name, options = Hash.new)
            # For backward compatibility only
            if !options.respond_to?(:to_hash)
                if options
                    options = Hash[:inheritance_mode => :expand]
                else
                    options = Hash[:inheritance_mode => :keep]
                end
            end
            options = Kernel.validate_options options,
                inheritance_mode: :expand
            inheritance_mode = options[:inheritance_mode]

            if !environment[name] && !inherited_environment[name] && !system_env[name]
                nil
            else
                inherited =
                    if inheritance_mode == :expand
                        inherited_environment[name] || []
                    elsif inheritance_mode == :keep && inherit?(name)
                        ["$#{name}"]
                    else []
                    end


                value = []
                [environment[name], inherited, system_env[name]].each do |paths|
                    (paths || []).each do |p|
                        if !value.include?(p)
                            value << p
                        end
                    end
                end
                value
            end
        end

        def update_var(name)
            if value = value(name)
                resolved_env[name] = value.join(File::PATH_SEPARATOR)
            else
                resolved_env.delete(name)
            end
        end

        def set_path(name, *paths)
            clear(name)
            add_path(name, *paths)
        end

        def add_path(name, *paths)
            paths = paths.map { |p| expand(p) }

            oldpath = (environment[name] ||= Array.new)
            paths.reverse.each do |path|
                path = path.to_str
                next if oldpath.include?(path)

                add(name, path)
                oldpath << path
                if name == 'RUBYLIB'
                    $LOAD_PATH.unshift path
                end
            end
        end

        def remove_path(name, *paths)
            paths.each do |p|
                environment[name].delete(p)
            end
            update_var(name)
        end

        def push_path(name, *values)
            if current = environment.delete(name)
                current = current.dup
                add_path(name, *values)
                add_path(name, *current)
            else
                add_path(name, *values)
            end
        end

        # @overload source_before
        #   List of scripts that should be sourced at the top of env.sh
        #
        #   @return [Array<String>] a list of paths that should be sourced at the
        #     beginning of the shell script generated by {export_env_sh}
        #
        # @overload source_before(path)
        #   @param [String] path a path that should be added to source_before
        #
        def source_before(file = nil)
            if file
                @source_before << file
            end
        end

        # @overload source_after
        #   List of scripts that should be sourced at the end of env.sh
        #
        #   @return [Array<String>] a list of paths that should be sourced at the
        #     end of the shell script generated by {export_env_sh}
        #
        # @overload source_after(path)
        #   @param [String] path a path that should be added to source_after
        #
        def source_after(file = nil)
            if file
                @source_after << file
            end
        end

        # Generates a shell script that sets the environment variable listed in
        # Autobuild.environment, following the inheritance setting listed in
        # Autobuild.inherited_environment.
        #
        # It also sources the files added by source_file
        def export_env_sh(io)
            @source_before.each do |path|
                io.puts SHELL_SOURCE_SCRIPT % path
            end

            variables = []
            environment.each do |name, _|
                variables << name
                value_with_inheritance = value(name, inheritance_mode: :keep)
                value_without_inheritance = value(name, inheritance_mode: :ignore)

                if !value_with_inheritance
                    shell_line = SHELL_UNSET_COMMAND % [name]
                elsif value_with_inheritance == value_without_inheritance # no inheritance
                    shell_line = SHELL_SET_COMMAND % [name, value_with_inheritance.join(File::PATH_SEPARATOR)]
                else
                    shell_line = SHELL_CONDITIONAL_SET_COMMAND % [name, value_with_inheritance.join(File::PATH_SEPARATOR), value_without_inheritance.join(File::PATH_SEPARATOR)]
                end
                io.puts shell_line
            end
            variables.each do |var|
                io.puts SHELL_EXPORT_COMMAND % [var]
            end
            @source_after.each do |path|
                io.puts SHELL_SOURCE_SCRIPT % [path]
            end
        end

        # DEPRECATED: use add_path instead
        def self.pathvar(path, varname)
            if File.directory?(path)
                if block_given?
                    return unless yield(path)
                end
                add_path(varname, path)
            end
        end

        def each_env_search_path(prefix, patterns)
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

        def arch_size
            if @arch_size
                return @arch_size
            end

            if File.file?('/usr/bin/dpkg-architecture')
                cmdline = ['/usr/bin/dpkg-architecture']
                if target_arch
                    cmdline << "-T" << target_arch
                end
                arch = `#{cmdline.join(" ")}`.split.grep(/DEB_TARGET_ARCH_BITS/).first
                if arch
                    @arch_size = Integer(arch.chomp.split('=').last)
                end
            end

            if !@arch_size
                @arch_size =
                    if RbConfig::CONFIG['host_cpu'] =~ /64/
                        64
                    else 32
                    end
            end
            @arch_size
        end

        def target_arch=(archname)
            @target_arch = archname
            @arch_size, @arch_names = nil
        end

        def target_arch
            @target_arch
        end

        def arch_names
            if @arch_names
                return @arch_names
            end

            result = Set.new
            if File.file?('/usr/bin/dpkg-architecture')
                cmdline = ['/usr/bin/dpkg-architecture']
                if target_arch
                    cmdline << "-T" << target_arch
                end
                arch = `#{cmdline.join(" ")}`.split.grep(/DEB_TARGET_MULTIARCH/).first
                if arch
                    result << arch.chomp.split('=').last
                end
            end
            @arch_names = result
        end

        def update_environment(newprefix, includes = nil)
            add_prefix(newprefix, includes)
        end

        # Returns the system-wide search path that is embedded in pkg-config
        def default_pkgconfig_search_suffixes
            found_path_rx = /Scanning directory '(.*\/)((?:lib|lib64|share)\/.*)'$/
            nonexistent_path_rx = /Cannot open directory '.*\/((?:lib|lib64|share)\/.*)' in package search path:.*/

            if !@default_pkgconfig_search_suffixes
                output = `LANG=C PKG_CONFIG_PATH= #{Autobuild.tool("pkg-config")} --debug 2>&1`.split("\n")
                found_paths = output.grep(found_path_rx).
                    map { |l| l.gsub(found_path_rx, '\2') }.
                    to_set
                not_found = output.grep(nonexistent_path_rx).
                    map { |l| l.gsub(nonexistent_path_rx, '\1') }.
                    to_set
                @default_pkgconfig_search_suffixes = found_paths | not_found
            end
            return @default_pkgconfig_search_suffixes
        end

        # Updates the environment when a new prefix has been added
        def add_prefix(newprefix, includes = nil)
            if !includes || includes.include?('PATH')
                if File.directory?("#{newprefix}/bin")
                    add_path('PATH', "#{newprefix}/bin")
                end
            end

            if !includes || includes.include?('PKG_CONFIG_PATH')
                each_env_search_path(newprefix, default_pkgconfig_search_suffixes) do |path|
                    add_path('PKG_CONFIG_PATH', path)
                end
            end

            if !includes || includes.include?(LIBRARY_PATH)
                ld_library_search = ['lib', 'lib/ARCH', 'libARCHSIZE']
                each_env_search_path(newprefix, ld_library_search) do |path|
                    if !Dir.glob(File.join(path, "lib*.#{LIBRARY_SUFFIX}")).empty?
                        add_path(LIBRARY_PATH, path)
                    end
                end
            end

            # Validate the new rubylib path
            if !includes || includes.include?('RUBYLIB')
                new_rubylib = "#{newprefix}/lib"
                if File.directory?(new_rubylib) && !File.directory?(File.join(new_rubylib, "ruby")) && !Dir["#{new_rubylib}/**/*.rb"].empty?
                    add_path('RUBYLIB', new_rubylib)
                end

                require 'rbconfig'
                %w{rubylibdir archdir sitelibdir sitearchdir vendorlibdir vendorarchdir}.
                    map { |key| RbConfig::CONFIG[key] }.
                    map { |path| path.gsub(/.*lib(?:32|64)?\//, '\\1') }.
                    each do |subdir|
                        if File.directory?("#{newprefix}/lib/#{subdir}")
                            add_path("RUBYLIB", "#{newprefix}/lib/#{subdir}")
                        end
                    end
            end
        end

        def isolate
            self.inherit = false
            push_path 'PATH', '/usr/local/bin', '/usr/bin', '/bin'
        end

        def prepare
            # Set up some important autobuild parameters
            inherit 'PATH', 'PKG_CONFIG_PATH', 'RUBYLIB', \
                'LD_LIBRARY_PATH', 'CMAKE_PREFIX_PATH', 'PYTHONPATH'
        end

        # Method called to filter the environment variables before they are set,
        # for instance to expand variables
        def expand(value)
            value
        end
    end

    def self.env=(env)
        @env = env
    end

    def self.env
        if !@env
            @env = Environment.new
            @env.prepare
        end
        @env
    end

    # @deprecated, use the API on {env} instead
    def self.env_reset(name = nil)
        env.reset(name)
    end
    # @deprecated, use the API on {env} instead
    def self.env_clear(name = nil)
        env.clear(name)
    end
    # @deprecated, use the API on {env} instead
    def self.env_set(name, *values)
        env.set(name, *values)
    end
    # @deprecated, use the API on {env} instead
    def self.env_inherit?(name = nil)
        env.inherit?(name)
    end
    # @deprecated, use the API on {env} instead
    def self.env_inherit=(value)
        env.inherit = value
    end
    # @deprecated, use the API on {env} instead
    def self.env_inherit(*names)
        env.inherit(*names)
    end
    # @deprecated, use the API on {env} instead
    def self.env_init_from_env(name)
        env.init_from_env(name)
    end
    # @deprecated, use the API on {env} instead
    def self.env_push(name, *values)
        env.push(name, *values)
    end
    # @deprecated, use the API on {env} instead
    def self.env_add(name, *values)
        env.add(name, *values)
    end
    # @deprecated, use the API on {env} instead
    def self.env_value(name, options = Hash.new)
        env.value(name, options)
    end
    # @deprecated, use the API on {env} instead
    def self.env_update_var(name)
        env.update_var(name)
    end
    # @deprecated, use the API on {env} instead
    def self.env_add_path(name, *paths)
        env.add_path(name, *paths)
    end
    # @deprecated, use the API on {env} instead
    def self.env_remove_path(name, *paths)
        env.remove_path(name, *paths)
    end
    # @deprecated, use the API on {env} instead
    def self.env_push_path(name, *values)
        env.push_path(name, *values)
    end
    # @deprecated, use the API on {env} instead
    def self.env_source_file(file)
        env.source_after(file)
    end
    # @deprecated, use the API on {env} instead
    def self.env_source_before(file = nil)
        env.source_before(file)
    end
    # @deprecated, use the API on {env} instead
    def self.env_source_after(file = nil)
        env.source_after(file)
    end
    # @deprecated, use the API on {env} instead
    def self.export_env_sh(io)
        env.export_env_sh(io)
    end
    # @deprecated, use the API on {env} instead
    def self.each_env_search_path(prefix, patterns)
        env.each_env_search_path(prefix, patterns)
    end
    # @deprecated, use the API on {env} instead
    def self.update_environment(newprefix, includes = nil)
        env.update_environment(newprefix, includes)
    end

    # @deprecated use {Env#add_path} on {.env} instead
    def self.pathvar(path, varname)
        if File.directory?(path)
            if block_given?
                return unless yield(path)
            end
            env.add_path(varname, path)
        end
    end

    def self.arch_size
        Autobuild.warn 'Autobuild.arch_size is deprecated, use Autobuild.env.arch_size instead'
        env.arch_size
    end

    def self.arch_names
        Autobuild.warn 'Autobuild.arch_names is deprecated, use Autobuild.env.arch_names instead'
        env.arch_names
    end
end

