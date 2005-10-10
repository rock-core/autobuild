class AutobuildException < Exception
    def mail?;  false end
    def fatal?; true end
    attr_accessor :target

    def initialize(target)
        @target = target
    end

    alias :exception_message :to_s 
    def to_s
        "#{target}: #{super}"
    end
end
class ConfigException  < AutobuildException; end
class PackageException < AutobuildException
    def mail?; true end
end


class SubcommandFailed < AutobuildException
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
class CommandNotFound < SubcommandFailed; end
class ImportException < SubcommandFailed; end
class BuildException  < SubcommandFailed; end
 
