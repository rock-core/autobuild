module Autobuild
    class Exception < RuntimeError
        def mail?;  false end
        def fatal?; true end
        attr_accessor :target, :phase

        def initialize(target = nil, phase = nil)
            @target = target
            @phase = phase
        end

        alias :exception_message :to_s 
        def to_s
            "#{target}: failed in #{phase} phase"
            "   #{super}"
        end
    end
    class ConfigException  < Exception; end
    class PackageException < Exception
        def mail?; true end
    end

    class CommandNotFound  < Exception; end
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
            @status = status
        end

        def to_s
            prefix = "#{super}\n    command '#{command}' failed"
            prefix << ": " + @orig_message if @orig_message
            prefix << "\n    see #{File.basename(logfile)} for details\n"
        end
    end
end

