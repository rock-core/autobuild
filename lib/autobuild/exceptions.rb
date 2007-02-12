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
            if target && phase
                "#{target}: failed in #{phase} phase\n   #{super}"
            elsif target
                "#{target}: #{super}"
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

        def to_s
            prefix = "#{super}\n    command '#{command}' failed"
            prefix << ": " + @orig_message if @orig_message
            prefix << "\n    see #{File.basename(logfile)} for details\n"
        end
    end
end

