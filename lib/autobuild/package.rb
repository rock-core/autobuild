module Autobuild
    TARGETS = %w{import prepare build}

    class << self
        attr_accessor :ignore_errors
    end
    
    # Basic block for the autobuilder
    #
    # The build is done in three phases:
    #   - import
    #   - prepare
    #   - build & install
    #
    # In the first stage checks the source out and/or updates it.
    #
    # In the second stage, packages create their dependency structure to handle
    # specific build systems. For instance, it is there that build systems like
    # CMake are handled so that reconfiguration happens if needed. In the same
    # way, it is there that code generation will happen as well.
    #
    # Finally, the build stage actually calls the package's build targets (of
    # the form "package_name-build", which will trigger the build if needed.
    class Package
	@@packages = {}
	@@provides = {}

	# the package name
	attr_reader     :name
	# set the source directory. If a relative path is given,
	# it is relative to Autobuild.srcdir. Defaults to #name
	attr_writer     :srcdir
        # set the importdir, this can be different than the sourcedir
        # if the source-root is in an subfolder of the package itself
        # then the importdir will be the root
        attr_writer     :importdir
	# set the installation directory. If a relative path is given,
	# it is relative to Autobuild.prefix. Defaults to ''
	attr_writer :prefix
        # Sets the log directory. If no value is set, the package will use
        # Autobuild.logdir
        attr_writer :logdir
        # The set of utilities attached to this package
        # @return [{String=>Utility}]
        attr_reader :utilities
        # Whether {#apply_post_install} has been called
        def applied_post_install?; !!@applied_post_install end
	
	# Sets importer object for this package. Defined for backwards compatibility.
	# Use the #importer attribute instead
	def import=(value)
	    @importer = value
	end
	# Sets an importer object for this package
	attr_accessor :importer

	# The list of packages this one depends upon
	attr_reader :dependencies

        # Some statistics about the commands that have been run
        attr_reader :statistics

        EnvOp = Struct.new :type, :name, :values

        # List of environment values added by this package with {#env_add},
        # {#env_add_path} or {#env_set}
        #
        # @return [Array<EnvOp>]
        attr_reader :env

        def add_stat(phase, duration)
            @statistics[phase] ||= 0
            @statistics[phase] += duration
        end

	# Absolute path to the source directory. See #srcdir=
	def srcdir; File.expand_path(@srcdir || name, Autobuild.srcdir) end
	# Absolute path to the import directory. See #importdir=
	def importdir; File.expand_path(@importdir || srcdir, Autobuild.srcdir) end
	# Absolute path to the installation directory. See #prefix=
	def prefix; File.expand_path(@prefix || '', Autobuild.prefix) end
        # Absolute path to the log directory for this package. See #logdir=
        def logdir
            if @logdir
                File.expand_path(@logdir, prefix)
            else
                Autobuild.logdir
            end
        end

	# The file which marks when the last sucessful install
	# has finished. The path is absolute
	#
	# A package is sucessfully built when it is installed
	def installstamp
            File.join(logdir, "#{name}-#{STAMPFILE}")
        end

        # Sets whether this package should update itself or not. If false, the
        # only importer operation that will be performed is checkout
        #
        # If nil, the global setting Autobuild.do_update is used
        attr_writer :update

        # True if this package should update itself when #import is called
        def update?
            if @update.nil?
                Autobuild.do_update
            else @update
            end
        end

        attr_writer :updated

        # Returns true if this package has already been updated. It will not be
        # true if the importer has been called while Autobuild.do_update was
        # false.
        def updated?; !!@updated end

	def initialize(spec = Hash.new)
            @srcdir = @importdir = @logdir = @prefix = nil
            @updated = false
            @update = nil
            @failed = nil
	    @dependencies   = Array.new
	    @provides       = Array.new
            @parallel_build_level = nil
            @statistics     = Hash.new
            @failures = Array.new
            @post_install_blocks = Array.new
            @applied_post_install = false
            @in_dir_stack = Array.new
            @utilities = Hash.new
            @env = Array.new

	    if Hash === spec
		name, depends = spec.to_a.first
	    else
		name, depends = spec, nil
	    end

	    name = name.to_s
	    @name = name
	    raise ConfigException, "package #{name} is already defined" if Autobuild::Package[name]
	    @@packages[name] = self

	    # Call the config block (if any)
	    yield(self) if block_given?

            self.doc_utility.source_dir ||= 'doc'
            self.doc_utility.target_dir ||= name

	    # Define the default tasks
	    task "#{name}-import" do
                isolate_errors { import }
            end
	    task :import => "#{name}-import"

	    # Define the prepare task
	    task "#{name}-prepare" => "#{name}-import" do
                isolate_errors { prepare }
            end
	    task :prepare => "#{name}-prepare"

	    task "#{name}-build"
	    task :build => "#{name}-build"

	    task(name) do
		Rake::Task["#{name}-import"].invoke
		Rake::Task["#{name}-prepare"].invoke
		Rake::Task["#{name}-build"].invoke
                if has_doc? && Autobuild.do_doc
                    Rake::Task["#{name}-doc"].invoke
                end
	    end
	    task :default => name
	    
            # The dependencies will be declared in the import phase,  so save
            # them there for now
            @spec_dependencies = depends
	end

        # Whether the package's source directory is present on disk
        def checked_out?
            File.directory?(srcdir)
        end

        def to_s
            "#<#{self.class} name=#{name}>"
        end
        def inspect; to_s end

        # @api private
        #
        # Adds a new operation to this package's environment setup. This is a
        # helper for the other env_* methods
        #
        # @param [EnvOp] op
        # @return [void]
        def add_env_op(op)
            env << op
        end

        # Add value(s) to a list-based environment variable
        #
        # This differs from {#env_add_path} in that a value can be added
        # multiple times in the list.
        #
        # @param [String] name the environment variable name
        # @param [Array<String>] values list of values to be added
        # @return [void]
        def env_add(name, *values)
            add_env_op EnvOp.new(:add, name, values)
        end

        # Add a new path to a PATH-like environment variable
        #
        # It differs from {#env_add} in its handling of duplicate values.  Any
        # value already existing will be removed, and re-appended to the value
        # so that it takes priority.
        #
        # @param [String] name the environment variable name
        # @param [Array<String>] values list of values. They will be joined
        #   using the platform's standard separator (e.g. : on Unices)
        # @return [void]
        def env_add_path(name, *values)
            add_env_op EnvOp.new(:add_path, name, values)
        end

        # Set an environment variable to a list of values
        #
        # @param [String] name the environment variable name
        # @param [Array<String>] values list of values. They will be joined
        #   using the platform's standard separator (e.g. : on Unices)
        # @return [void]
        def env_set(name, *values)
            add_env_op EnvOp.new(:set, name, values)
        end

        # Add a prefix to be resolved into the environment
        #
        # Autoproj will update all "standard" environment variables based on
        # what it finds as subdirectories from the prefix
        def env_add_prefix(prefix, includes = nil)
            add_env_op EnvOp.new(:add_prefix, prefix, [includes])
        end

        # Hook called by autoproj to set up the default environment for this
        # package
        #
        # By default, it calls {#env_add_prefix} with this package's prefix
        def update_environment
            env_add_prefix prefix
        end

        class IncompatibleEnvironment < ConfigException; end

        # @api private
        #
        # Apply this package's environment to the given {Environment} object
        #
        # It does *not* apply the dependencies' environment. Call
        # {#resolved_env} for that.
        #
        # @param [Environment] env the environment to be updated
        # @param [Set] set a set of environment variable names which have
        #   already been set by a {#env_set}. Autoproj will verify that only one
        #   package sets a variable as to avoid unexpected conflicts.
        # @return [Array<EnvOp>] list of environment-modifying operations
        #   applied so far
        def apply_env(env, set = Hash.new, ops = Array.new)
            self.env.each do |env_op|
                next if ops.last == env_op
                if env_op.type == :set
                    if last = set[env_op.name]
                        last_pkg, last_values = *last
                        if last_values != env_op.values
                            raise IncompatibleEnvironment, "trying to reset #{env_op.name} to #{env_op.values} in #{self.name} but this conflicts with #{last_pkg.name} already setting it to #{last_values}"
                        end
                    else
                        set[env_op.name] = [self, env_op.values]
                    end
                end
                env.send(env_op.type, env_op.name, *env_op.values)
                ops << env_op
            end
            ops
        end

        # @api private
        #
        # Updates an {Environment} object with the environment of the package's
        # dependencies
        def resolve_dependency_env(env, set, ops)
            all_dependencies.each do |pkg_name|
                pkg = Autobuild::Package[pkg_name]
                ops = pkg.apply_env(env, set, ops)
            end
            ops
        end

        # This package's environment
        def full_env(root = Autobuild.env)
            set = Hash.new
            env = root.dup
            ops = Array.new
            ops = resolve_dependency_env(env, set, ops)
            apply_env(env, set, ops)
            env
        end

        # Find a file in a path-like environment variable
        def find_in_path(file, envvar = 'PATH')
            full_env.find_in_path(file, envvar)
        end

        # Resolves this package's environment into Hash form
        #
        # @param [Environment] root the base environment object to update
        # @return [Hash<String,String>] the full environment
        # @see Autobuild::Environment#resolved_env
        def resolved_env(root = Autobuild.env)
            full_env(root).resolved_env
        end

        # Called before a forced build. It should remove all the timestamp and
        # target files so that all the build phases of this package gets
        # retriggered. However, it should not clean the build products.
        def prepare_for_forced_build
            if File.exist?(installstamp)
                FileUtils.rm_f installstamp
            end
        end

        # Called when the user asked for a full rebuild. It should delete the
        # build products so that a full build is retriggered.
        def prepare_for_rebuild
            prepare_for_forced_build

            if File.exist?(installstamp)
                FileUtils.rm_f installstamp
            end
        end

        # Returns true if one of the operations applied on this package failed
        def failed?
            @failed
        end

        # If something failed on this package, returns the corresponding
        # exception object. Otherwise, returns nil
        attr_reader :failures

        # If Autobuild.ignore_errors is set, an exception raised from within the
        # provided block will be filtered out, only displaying a message instead
        # of stopping the build
        #
        # Moreover, the package will be marked as "failed" and isolate_errors
        # will subsequently be a noop. I.e. if +build+ fails, +install+ will do
        # nothing.
        def isolate_errors(options = Hash.new)
            if !options.kind_of?(Hash)
                options = Hash[mark_as_failed: true]
            end
            options = validate_options options,
                mark_as_failed: true,
                ignore_errors: Autobuild.ignore_errors

            # Don't do anything if we already have failed
            if failed?
                if !options[:ignore_errors]
                    raise AlreadyFailedError, "attempting to do an operation on a failed package"
                end
                return
            end

            begin
                toplevel = !Thread.current[:isolate_errors]
                Thread.current[:isolate_errors] = true
                yield
            rescue InteractionRequired
                raise
            rescue Interrupt
                raise
            rescue ::Exception => e
                @failures << e
                if options[:mark_as_failed]
                    @failed = true
                end

                if options[:ignore_errors]
                    lines = e.to_s.split("\n")
                    if lines.empty?
                        lines = e.message.split("\n")
                    end
                    if lines.empty?
                        lines = ["unknown error"]
                    end
                    message(lines.shift, :red, :bold)
                    lines.each do |line|
                        message(line)
                    end
                    nil
                else
                    raise
                end
            ensure
                if toplevel
                    Thread.current[:isolate_errors] = false
                end
            end
        end

        # Call the importer if there is one. Autodetection of "provides" should
        # be done there as well.
        #
        # (see Importer#import)
	def import(options = Hash.new)
            if !options.respond_to?(:to_hash)
                options = Hash[only_local: options]
            end

            if @importer
                @importer.import(self, options)
            elsif update?
                message "%s: no importer defined, doing nothing"
            end

            # Add the dependencies declared in spec
            depends_on(*@spec_dependencies) if @spec_dependencies
        end

        # Create all the dependencies required to reconfigure and/or rebuild the
        # package when required. The package's build target is called
        # "package_name-build".
	def prepare
            super if defined? super

            stamps = dependencies.map { |p| Package[p].installstamp }

            file installstamp => stamps do
                isolate_errors { install }
            end
            task "#{name}-build" => installstamp
        end

        def process_formatting_string(msg, *prefix_style)
            prefix, suffix = [], []
            msg.split(" ").each do |token|
                if token =~ /%s/
                    suffix << token.gsub(/%s/, name)
                elsif suffix.empty?
                    prefix << token
                else suffix << token
                end
            end
            if suffix.empty?
                return msg
            elsif prefix_style.empty?
                return (prefix + suffix).join(" ")
            else
                return [Autobuild.color(prefix.join(" "), *prefix_style), *suffix].join(" ")
            end
        end

        # Display a progress message. %s in the string is replaced by the
        # package name
        def warn(warning_string)
            message("  WARN: #{warning_string}", :magenta)
        end

        # Display a progress message. %s in the string is replaced by the
        # package name
        def error(error_string)
            message("  ERROR: #{error_string}", :red, :bold)
        end

        # Display a progress message. %s in the string is replaced by the
        # package name
        def message(*args)
            if !args.empty?
                args[0] = "  #{process_formatting_string(args[0])}"
            end
            Autobuild.message(*args)
        end

        def progress_start(*args, &block)
            args[0] = process_formatting_string(args[0], :bold)
            if args.last.kind_of?(Hash)
                options, raw_options = Kernel.filter_options args.last, :done_message
                if options[:done_message]
                    options[:done_message] = process_formatting_string(options[:done_message])
                end
                args[-1] = options.merge(raw_options)
            end
                
            Autobuild.progress_start(self, *args, &block)
        end

        def progress(*args)
            args[0] = process_formatting_string(args[0], :bold)
            Autobuild.progress(self, *args)
        end

        def progress_done(done_message = nil)
            if done_message && Autobuild.has_progress_for?(self)
                progress(process_formatting_string(done_message))
            end
            Autobuild.progress_done(self)
        end

        def apply_post_install
            Autobuild.post_install_handlers.each do |b|
                Autobuild.apply_post_install(self, b)
            end
            @post_install_blocks.each do |b|
                Autobuild.apply_post_install(self, b)
            end
            @applied_post_install = true
        end

        # Install the result in prefix
        def install
            apply_post_install

            # Safety net for forgotten progress_done
            progress_done

            Autobuild.touch_stamp(installstamp)
        end

        def run(*args, &block)
            if args.last.kind_of?(Hash)
                options = args.pop
            else
                options = Hash.new
            end
            options[:env] = options.delete(:resolved_env) ||
                (options[:env] || Hash.new).merge(resolved_env)
            Autobuild::Subprocess.run(self, *args, options, &block)
        end

        module TaskExtension
            attr_accessor :package
        end

        def source_tree(*args, &block)
            task = Autobuild.source_tree(*args, &block)
            task.extend TaskExtension
            task.package = self
            task
        end

        # Calls Rake to define a file task and then extends it with TaskExtension
        def file(*args, &block)
            task = super
            task.extend TaskExtension
            task.package = self
            task
        end

        # Calls Rake to define a plain task and then extends it with TaskExtension
        def task(*args, &block)
            task = super
            task.extend TaskExtension
            task.package = self
            task
        end

        def doc_dir=(value); doc_utility.source_dir = value end
        def doc_dir; doc_utility.source_dir end
        def doc_target_dir=(value); doc_utility.target_dir = value end
        def doc_target_dir; doc_utility.target_dir end
        def doc_task(&block); doc_utility.task(&block) end
        def generates_doc?; doc_utility.enabled? end
        def enable_doc; doc_utility.enabled = true end
        def disable_doc; doc_utility.enabled = false end
        def install_doc; doc_utility.install end
        def doc_disabled; doc_utility.disabled end
        def has_doc?; doc_utility.has_task? end

	def post_install(*args, &block)
	    if args.empty?
		@post_install_blocks << block
	    elsif !block
		@post_install_blocks << args
	    else
		raise ArgumentError, "cannot set both arguments and block"
	    end
	end

        # Returns the name of all the packages +self+ depends on
        def all_dependencies(result = Set.new)
            dependencies.each do |pkg_name|
                pkg = Autobuild::Package[pkg_name]
                if !result.include?(pkg.name)
                    result << pkg.name
                    pkg.all_dependencies(result)
                end
            end
            result
        end

        # Returns true if this package depends on +package_name+ and false
        # otherwise.
        def depends_on?(package_name)
            @dependencies.include?(package_name)
        end

	# This package depends on +packages+. It means that its build will
        # always be triggered after the packages listed in +packages+ are built
        # and installed.
	def depends_on(*packages)
	    packages.each do |p|
                p = p.name if p.respond_to?(:name)
                raise ArgumentError, "#{p.inspect} should be a string" if !p.respond_to? :to_str
		p = p.to_str
		next if p == name
		unless pkg = Package[p]
		    raise ConfigException.new(self), "package #{p}, listed as a dependency of #{self.name}, is not defined"
		end

                next if @dependencies.include?(pkg.name)

                if Autobuild.verbose
                    Autobuild.message "#{name} depends on #{pkg.name}"
                end

		task "#{name}-import"  => "#{pkg.name}-import"
		task "#{name}-prepare" => "#{pkg.name}-prepare"
		task "#{name}-build"   => "#{pkg.name}-build"
		@dependencies << pkg.name
	    end
	end

	# Declare that this package provides +packages+. In effect, the names
        # listed in +packages+ are aliases for this package.
	def provides(*packages)
	    packages.each do |p|
                raise ArgumentError, "#{p.inspect} should be a string" if !p.respond_to? :to_str
		p = p.to_str
		next if p == name
                next if @provides.include?(name)

		@@provides[p] = self 

                if Autobuild.verbose
                    Autobuild.message "#{name} provides #{p}"
                end

		task p => name
		task "#{p}-import" => "#{name}-import"
		task "#{p}-prepare" => "#{name}-prepare"
		task "#{p}-build" => "#{name}-build"
		@provides << p
	    end
	end

	# Iterates on all available packages
	# if with_provides is true, includes the list
	# of package aliases
	def self.each(with_provides = false, &p)
            if !p
                return enum_for(:each, with_provides)
            end

	    @@packages.each(&p) 
	    @@provides.each(&p) if with_provides
	end

	# Gets a package from its name
	def self.[](name)
	    @@packages[name.to_s] || @@provides[name.to_s]
	end

        # Removes all package definitions
        def self.clear
            @@packages.clear
            @@provides.clear
        end

        # Sets the level of parallelism authorized while building this package
        #
        # See #parallel_build_level and Autobuild.parallel_build_level for more
        # information.
        #
        # Note that not all package types use this value
        def parallel_build_level=(value)
            @parallel_build_level = Integer(value)
        end

        # Returns the level of parallelism authorized during the build for this
        # particular package. If not set, defaults to the system-wide option 
        # (Autobuild.parallel_build_level and Autobuild.parallel_build_level=).
        #
        # The default value is the number of CPUs on this system.
        def parallel_build_level
            if @parallel_build_level.nil?
                Autobuild.parallel_build_level
            elsif !@parallel_build_level || @parallel_build_level <= 0
                1
            else
                @parallel_build_level
            end
        end

        def working_directory
            @in_dir_stack.last
        end

        def in_dir(directory)
            @in_dir_stack << directory
            yield

        ensure
            @in_dir_stack.pop
        end

        def disabled?
            @disabled
        end

        # Makes sure that the specified phases of this package will be no-ops
        def disable_phases(*phases)
            phases.each do |phase|
                task "#{name}-#{phase}"
                t = Rake::Task["#{name}-#{phase}"]
                t.disable!
            end
        end

        # Make sure that this package will be ignored in the build
        def disable(phases = Autobuild.all_phases)
            @disabled = true
            disable_phases(*phases)
            task(installstamp)
            t = Rake::Task[installstamp]
            t.disable!
        end

        def utility(utility_name)
            utilities[utility_name] ||= Autobuild.create_utility(utility_name, self)
        end


        def method_missing(m, *args, &block)
            case m.to_s
            when /(\w+)_utility$/
                utility_name = $1
                if !args.empty?
                    raise ArgumentError, "expected 0 arguments and got #{args.size}"
                end
                begin
                    return utility(utility_name)
                rescue ArgumentError => e
                    raise NoMethodError.new(m), e.message, e.backtrace
                end
            end
            super
        end
    end

    def self.package_set(spec)
	spec.each do |name, packages|
	    Autobuild::TARGETS.each do |target|
		task "#{name}-#{target}" => packages.map { |dep| "#{dep}-#{target}" }
	    end
	end
    end
end

