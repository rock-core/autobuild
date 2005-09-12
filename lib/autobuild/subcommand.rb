require 'autobuild/logging'

def subcommand(target, type, *command)
    # Filter nil and empty? in command
    command.reject! { |o| o.nil? || (o.respond_to?(:empty?) && o.empty?) }
    command.collect! { |o| o.to_s }
    logname = "#{$LOGDIR}/#{target}-#{type}.log"
    puts "#{target}: running #{command.join(" ")}\n    (output goes to #{logname})"

    input_streams = command.collect { |o| $1 if o =~ /^\<(.+)/ }.compact
    command.reject! { |o| o =~ /^\<(.+)/ }


    status = File.open(logname, "a") do |logfile|
        pread, pwrite = IO.pipe

        pid = fork { 
            Process.setpriority(Process::PRIO_PROCESS, 0, $NICE) if $NICE
            if $VERBOSE
                $stderr.dup.reopen(logfile.dup)
                $stdout.dup.reopen(logfile.dup)
            else
                $stderr.reopen(logfile.dup)
                $stdout.reopen(logfile.dup)
            end

            if !input_streams.empty?
                pwrite.close
                $stdin.reopen(pread)
            end
           
            if !exec(*command)
                raise "Error running command"
            end
        }

        # Feed the input
        pread.close
        input_streams.each do |infile|
            File.open(infile) do |instream|
                instream.each_line { |line| pwrite.write(line) }
            end
        end
        pwrite.close

        childpid, childstatus = Process.wait2(pid)
        childstatus
    end

    if status.exitstatus > 0
        raise SubcommandFailed.new(target, command.join(" "), logname, status.exitstatus)
        return false
    else
        return true
    end
end

