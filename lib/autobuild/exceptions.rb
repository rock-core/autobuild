module Autobuild
    ## Base class for all Autobuild exceptions
    class Exception < RuntimeError
        ## If the error should be reported by mail
        def mail?;  false end
        ## If the error is fatal
        def fatal?; true end
        ## If the error can be retried
        def retry?; @retry end
        attr_accessor :target, :phase

        ## Creates a new exception which occured while doing *phase* 
        # in *target*
        def initialize(target = nil, phase = nil, options = Hash.new)
            options = Kernel.validate_options options, retry: true
            @target, @phase = target, phase
            @retry = options[:retry]
        end

        alias :exception_message :to_s 
        def to_s
            dir =
                if target.respond_to?(:srcdir)
                    "(#{target.srcdir})"
                end
            target_name =
                if target.respond_to?(:name)
                    target.name
                else target.to_str
                end

            if target && phase
                "#{target_name}#{dir}: failed in #{phase} phase\n    #{super}"
            elsif target
                "#{target_name}#{dir}: #{super}"
            else
                super
            end
        end
    end

    ## There is an error/inconsistency in the configuration
    class ConfigException  < Exception
        def initialize(target = nil, phase = nil, options = Hash.new)
            options, other_options = Kernel.filter_options options,
                retry: false
            super(target, phase, options.merge(other_options))
        end
    end
    ## An error occured in a package
    class PackageException < Exception
        def mail?; true end

        def initialize(target = nil, phase = nil, options = Hash.new)
            options, other_options = Kernel.filter_options options,
                retry: false
            super(target, phase, options.merge(other_options))
        end
    end

    # Exception thrown by importers when calling update with the reset flag but
    # some conditiions make the reset impossible
    class ImporterCannotReset < PackageException
    end

    ## The subcommand is not found
    class CommandNotFound  < Exception; end
    ## An error occured while running a subcommand
    class SubcommandFailed < Exception
        def mail?; true end
        attr_writer :retry
        attr_reader :command, :logfile, :status, :output
        def initialize(*args)
            if args.size == 1
                sc = args[0]
                target, command, logfile, status, output = 
                    sc.target, sc.command, sc.logfile, sc.status, sc.output
                @orig_message = sc.exception_message
            elsif args.size == 4 || args.size == 5
                target, command, logfile, status, output = *args
            else
                raise ArgumentError, "wrong number of arguments, should be 1 or 4..5"
            end

            super(target)
            @command = command
            @logfile = logfile
            @status  = status
            @output = output || Array.new
        end

        def to_s
            msg = super
            if @orig_message
                msg << "\n     #{@orig_message}"
            end
            msg << "\n    see #{logfile} for details"

            # If we do not have a status, it means an error occured in the
            # launching process. More importantly, it means we already have a
            # proper explanation for it. Don't display the logfile at all.
            if status 
                lines = @output
                logsize = Autobuild.displayed_error_line_count
                if logsize != Float::INFINITY && lines.size > logsize
                    lines = lines[-logsize, logsize]
                end
                msg << "\n    last #{lines.size} lines are:\n\n"
                lines.each do |l|
                    msg << "    #{l}\n"
                end
            end
            msg
        end
    end

    # Exception raised in contexts where user interaction is forbidden but
    # required by the import/build process
    #
    # This is for instance used during package import if the importer has to ask
    # the user a question and allow_interactive is false
    class InteractionRequired < RuntimeError; end

    class AlreadyFailedError < RuntimeError; end

    # The exception type that is used to report multiple errors that occured
    # when ignore_errors is set
    class CompositeException < Autobuild::Exception
        # The array of exception objects representing all the errors that
        # occured during the build
        attr_reader :original_errors

        def initialize(original_errors)
            @original_errors = original_errors
        end

        def mail?; true end

        def to_s
            result = ["#{original_errors.size} errors occured"]
            original_errors.each_with_index do |e, i|
                result << "(#{i}) #{e.to_s}"
            end
            result.join("\n")
        end
    end
end
