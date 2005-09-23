class SubcommandFailed < Exception
    def mail?;  false end
    def fatal?; true end

    attr_reader :target, :command, :logfile, :status
    def initialize(target, command, logfile, status)
        @target = target
        @command = command
        @logfile = logfile
        @status = status
    end
end
        
class ConfigException < Exception
    def mail?;  false end
    def fatal?; true end

    def initialize(target = nil)
        @target = target
    end
    attr_accessor :target
end

class PackageException < Exception
    def mail?; true end
    def fatal?; true end

    def initialize(target = nil)
        @target = target
    end
    attr_accessor :target
end

class ImportException < SubcommandFailed
    def mail?;  true end
    def fatal?; true end

    def initialize(subcommand)
        super(subcommand.target, subcommand.command, subcommand.logfile, subcommand.status)
    end
end

class BuildException < SubcommandFailed
    def mail?;  true end
    def fatal?; true end

    def initialize(subcommand)
        super(subcommand.target, subcommand.command, subcommand.logfile, subcommand.status)
    end
end

