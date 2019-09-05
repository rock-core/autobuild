module Autobuild
    # Utilities are post-build things that can be executed on packages
    #
    # Canonical examples are documentation generation and tests
    class Utility
        # This utility's name
        attr_reader :name
        # @return [Package] the package on which this utility object acts
        attr_reader :package
        # @return [String,nil] the reference directory for {#source_dir=}. If
        #   nil, will use the package's source directory
        attr_accessor :source_ref_dir

        # Whether #install should be called even if the task failed
        #
        # The default is false. Set it to true for instance if the utility
        # results are a report of the success/errors (e.g. test run results)
        def install_on_error?
            @install_on_error
        end

        def initialize(name, package, install_on_error: false)
            @name = name
            @task = nil
            @package = package
            @available = true
            @enabled   = true
            @source_ref_dir = nil
            @source_dir = nil
            @target_dir = nil
            @install_on_error = install_on_error

            @invoked = false
            @success = false
            @installed = false
        end

        # Directory in which the utility will generate some files The
        # interpretation of relative directories is package-specific. The
        # default implementation interpret them as relative to the source
        # directory. Set {#source_ref_dir=}
        #
        # @return [String,nil] the target directory, or nil if this utility does
        #   not need any special source directory
        attr_writer :source_dir

        # Absolute path to where this utulity should output its results. Returns nil if
        # {source_dir} has not been set.
        def source_dir
            File.expand_path(@source_dir, source_ref_dir || package.srcdir) if @source_dir
        end

        # Directory in which the utility would install some files.
        # If it is relative, it is interpreted as relative to the utility's
        # prefix directory (Autobuild.#{name}_prefix)
        #
        # @return [String,nil] the target directory, or nil if this utility does
        #   not install anything
        attr_writer :target_dir

        # Absolute path to where the utility product files have to be installed.
        # Returns nil if {target_dir} is not set.
        #
        # @return [String,nil]
        def target_dir
            if @target_dir
                utility_prefix = Autobuild.send("#{name}_prefix") || name
                File.expand_path(@target_dir,
                    File.expand_path(utility_prefix, package.prefix))
            else
                File.join(package.logdir, "#{name}-results", package.name)
            end
        end

        # Defines the task code for this utility. The given block is called and
        # then the utility byproducts get installed (if any).
        #
        # The block is invoked in the package's source directory
        #
        # In general, specific package types define a meaningful #with_XXX
        # method that call this method internally
        #
        # @return [Rake::Task]
        def task(&block)
            return if @task

            @task = package.task task_name do
                # This flag allows to disable this utility's task
                # once {task} has been called
                if enabled?
                    @installed = false
                    catch(:disabled) do
                        package.isolate_errors do
                            call_task_block(&block)
                        end
                    end
                end
            end

            package.task name => task_name
            @task
        end

        def call_task_block
            @invoked = true

            yield if block_given?
            @success = true

            # Allow the user to install manually in the task
            # block
            install if !@installed && target_dir
        rescue Interrupt
            raise
        rescue ::Exception => e
            install if install_on_error? && !@installed && target_dir
            @success = false

            if Autobuild.send("pass_#{name}_errors")
                raise
            else
                package.warn "%s: failed to call #{name}"
                if e.kind_of?(SubcommandFailed)
                    package.warn "%s: see #{e.logfile} for more details"
                else
                    package.warn "%s: #{e.message}"
                end
            end
        end

        # True if this utility would do something, and false otherwise
        #
        # This will return true only if a task has been by calling {task} _and_
        # the utility has not been explicitly disabled by setting the {enabled}
        # attribute to false
        #
        # @return [Boolean]
        def available?
            @available && (source_dir && @task)
        end

        # True if this utility should be executed
        #
        # @return [Boolean]
        def enabled?
            @enabled && available?
        end

        # Allows to override the utility's availability (i.e. whether this
        # utility is available on the underlying package) regardless of whether
        # {task} got called or not
        #
        # This is mainly used to fine-tune packages whose base type enables the
        # utility (e.g. testing) but the actual package does not have it
        attr_writer :available

        # Allows to disable the utility regardless of the value of {available?}
        attr_writer :enabled

        def install
            unless File.directory?(source_dir)
                raise "#{source_dir} was expected to be a directory, but it is not. "\
                    "Check the package's #{name} generation. "\
                    "The generated #{name} products should be in #{source_dir}"
            end

            target_dir  = self.target_dir
            source_dir  = self.source_dir
            FileUtils.rm_rf   target_dir
            FileUtils.mkdir_p File.dirname(target_dir)
            FileUtils.cp_r    source_dir, target_dir
            Autoproj.message "  copied #{name} results for #{package.name} "\
                "from #{source_dir} to #{target_dir}"

            @installed = true
        end

        # True if the utility has been invoked
        def invoked?
            @invoked
        end

        # True if the utility has been successful
        #
        # Combine with {#invoked?} to determine whether 'false' means 'not run'
        # or 'failed'
        def success?
            @success
        end

        # True if the utility's results have been installed
        def installed?
            @installed
        end

        # Can be called in the block given to {task} to announce that the
        # utility is to be disabled for that package. This is mainly used
        # when a runtime check is necessary to know if a package can run
        # this utility or not.
        def disabled
            throw :disabled
        end

        # The name of the Rake task
        #
        # @return [String]
        def task_name
            "#{package.name}-#{name}"
        end

        # True if the underlying package already has a task generated by this
        # utility
        #
        # @return [Boolean]
        def has_task?
            Rake.application.lookup(task_name)
        end
    end
end
