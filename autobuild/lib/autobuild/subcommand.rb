require 'autobuild/logging'

def subcommand(target, type, *command)
    # Filter nil and empty? in command
    command = command.reject { |o| o.nil? || (o.respond_to?(:empty?) && o.empty?) }
    command.collect! { |o| o.to_s }

    logname = "#{$LOGDIR}/#{target}-#{type}.log"
    puts "#{target}: running #{command.join(" ")}\n    (output goes to #{logname})"

    status = File.open(logname, "a") { |logfile|
        pid = fork { 
            Process.setpriority(Process::PRIO_PROCESS, 0, $NICE) if $NICE
            if $VERBOSE
                $stderr.dup.reopen(logfile.dup)
                $stdout.dup.reopen(logfile.dup)
            else
                $stderr.reopen(logfile.dup)
                $stdout.reopen(logfile.dup)
            end
           
            if !exec(*command)
                raise "Error running command"
            end
        }
        childpid, childstatus = Process.wait2(pid)
        childstatus
    }

    if status.exitstatus > 0
        raise SubcommandFailed.new(target, command.join(" "), logname, status.exitstatus)
        return false
    else
        return true
    end
end

