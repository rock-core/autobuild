module Autobuild
    ## Base class for all Autobuild exceptions
    class Exception < RuntimeError
        ## If the error should be reported by mail
        def mail?;  false end
        ## If the error is fatal
        def fatal?; true end
        attr_accessor :target, :phase

        ## Creates a new exception which occured while doing *phase* 
        # in *target*
        def initialize(target = nil, phase = nil)
            @target, @phase = target, phase
        end

        alias :exception_message :to_s 
        def to_s
            dir =
                if target.respond_to?(:srcdir)
                    "(#{target.srcdir})"
                else
                    puts target.inspect
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
    class ConfigException  < Exception; end
    ## An error occured in a package
    class PackageException < Exception
        def mail?; true end
    end

    ## The subcommand is not found
    class CommandNotFound  < Exception; end
    ## An error occured while running a subcommand
    class SubcommandFailed < Exception
        def mail?; true end
        attr_reader :command, :logfile, :status
        def initialize(*args)
            if args.size == 1
                sc = args[0]
                target, command, logfile, status = 
                    sc.target, sc.command, sc.logfile, sc.status
                @orig_message = sc.exception_message
            elsif args.size == 4
                target, command, logfile, status = *args
            else
                raise ArgumentError, "wrong number of arguments, should be 1 or 4"
            end

            super(target)
            @command = command
            @logfile = logfile
            @status  = status
        end

        ERROR_LINES = 10

        def to_s
            prefix = super
            if @orig_message
                prefix << "\n     #{@orig_message}"
            end
            prefix << "\n    see #{logfile} for details"

            # If we do not have a status, it means an error occured in the
            # launching process. More importantly, it means we already have a
            # proper explanation for it. Don't display the logfile at all.
            if status
                lines = File.readlines(logfile)
                if lines.size > ERROR_LINES
                    lines = lines[-ERROR_LINES, ERROR_LINES]
                end
                prefix << "\n    last #{lines.size} lines are:\n\n"
                lines.each do |l|
                    prefix << "    #{l}"
                end
            end
            prefix
        end
    end
end

