require 'autobuild/logging'

def subcommand(target, type, command)
    logname = "#{$LOGDIR}/#{target}-#{type}.log"
    puts "#{target}: running #{command}\n    (output goes to #{logname})"

    status = File.open(logname, "a") { |logfile|
        pid = fork { 
            if $VERBOSE
                $stderr.dup.reopen(logfile.dup)
                $stdout.dup.reopen(logfile.dup)
            else
                $stderr.reopen(logfile.dup)
                $stdout.reopen(logfile.dup)
            end
           
            if !exec(*command.split(" "))
                raise "Error running command"
            end
        }
        childpid, childstatus = Process.wait2(pid)
        childstatus
    }

    if status.exitstatus > 0
        raise SubcommandFailed.new(target, command, logname, status.exitstatus)
        return false
    else
        return true
    end
end

