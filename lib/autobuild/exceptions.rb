class AutobuildException < Exception
    def mail?;  false end
    def fatal?; true end
    attr_accessor :target

    def initialize(target)
        @target = target
    end

    def to_s
        "#{target}: #{message}"
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
"#{target}: #{super}
    command '#{command}' failed with status #{status}
    see #{File.basename(logfile)} for details
"
    end
end
class ImportException < SubcommandFailed; end
class BuildException  < SubcommandFailed; end
    

