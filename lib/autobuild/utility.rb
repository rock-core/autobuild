module Autobuild
    # Utilities are post-build things that can be executed on packages
    #
    # Canonical examples are documentation generation and tests
    class Utility
        # This utility's name
        attr_reader :name
        # @return [Package] the package on which this utility object acts
        attr_reader :package
        # @return [String] the reference directory for {#source_dir=}
        attr_accessor :source_ref_dir

        def initialize(name, package)
            @name = name
            @package = package
            @enabled = true
            @source_ref_dir = package.srcdir
        end

        # Directory in which the utility will generate some files The
        # interpretation of relative directories is package-specific. The
        # default implementation interpret them as relative to the source
        # directory. Set {#source_ref_dir=} to override.
        #
        # @return [String,nil] the target directory, or nil if this utility does
        #   not need any special source directory
        attr_writer :source_dir

        # Absolute path to where this utulity should output its results. Returns nil if
        # {source_dir} has not been set.
        def source_dir
            if @source_dir
                File.expand_path(@source_dir, source_ref_dir)
            end
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
                File.expand_path(@target_dir, File.expand_path(Autobuild.send("#{name}_prefix") || name,  package.prefix))
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
        def task
            return if @task
            @task = package.task task_name do
                # This flag allows to disable this utility's task
                # once {task} has been called
                if enabled?
                    @installed = false
                    catch(:disabled) do
                        begin
                            yield if block_given?

                            # Allow the user to install manually in the task
                            # block
                            unless @installed
                                install
                            end

                        rescue Interrupt
                            raise
                        rescue ::Exception => e
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
                    end
                end
            end

            package.task name => task_name 
            @task
        end

        # True if this utility would do something, and false otherwise
        #
        # This will return true only if a task has been by calling {task} _and_
        # the utility has not been explicitly disabled by setting the {enabled}
        # attribute to false
        def enabled?
            if !@enabled
                return false
            else
                return source_dir && @task
            end
        end

        # Allows to force {enabled?} to return false, regardless of whether
        # {task} has been called or not
        #
        # This is mainly used for package types that have an e.g. documentation
        # task by default, so that some packages can disable it.
        attr_writer :enabled

        def install
            if !File.directory?(source_dir)
                raise "#{source_dir} was expected to be a directory, but it is not. Check the package's #{name} generation. The generated #{name} products should be in #{source_dir}"
            end

            target_dir  = self.target_dir
            source_dir  = self.source_dir
            FileUtils.rm_rf   target_dir
            FileUtils.mkdir_p File.dirname(target_dir)
            FileUtils.cp_r    source_dir, target_dir

            @installed = true
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
            !!Rake.application.lookup(task_name)
        end
    end
end

