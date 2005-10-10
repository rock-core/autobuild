require 'autobuild/reporting'

module Subprocess
    @@nice = 0
    def self.nice=(value)
        @@nice = value
    end

    CONTROL_COMMAND_NOT_FOUND = 1
    CONTROL_UNEXPECTED = 2
    def self.run(target, type, *command)
        # Filter nil and empty? in command
        command.reject! { |o| o.nil? || (o.respond_to?(:empty?) && o.empty?) }
        command.collect! { |o| o.to_s }
        logname = "#{$LOGDIR}/#{target}-#{type}.log"
        puts "#{target}: running #{command.join(" ")}\n    (output goes to #{logname})"

        input_streams = command.collect { |o| $1 if o =~ /^\<(.+)/ }.compact
        command.reject! { |o| o =~ /^\<(.+)/ }

        status = File.open(logname, "a") do |logfile|
            pread, pwrite = IO.pipe # to feed subprocess stdin 
            cread, cwrite = IO.pipe # to control that exec goes well

            pid = fork { 
                cwrite.sync = true
                begin
                    Process.setpriority(Process::PRIO_PROCESS, 0, @@nice)
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
                   
                    exec(*command)
                rescue Errno::ENOENT
                    cwrite.write([CONTROL_COMMAND_NOT_FOUND].pack('I'))
                    raise
                rescue Exception
                    cwrite.write([CONTROL_UNEXPECTED].pack('I'))
                    raise
                end
            }

            # Feed the input
            pread.close
            begin
                input_streams.each do |infile|
                    File.open(infile) do |instream|
                        instream.each_line { |line| pwrite.write(line) }
                    end
                end
            rescue Errno::ENOENT => e
                logfile.puts "Cannot open input files: #{e.message}"
                raise SubcommandFailed.new(target, command.join(" "), logname, 0), e.message
            end
            pwrite.close

            # Get control status
            cwrite.close
            value = cread.read(4)
            if value
                # An error occured
                value = value.unpack('I').first
                if value == CONTROL_COMMAND_NOT_FOUND
                    raise SubcommandFailed.new(target, command.join(" "), logname, 0), "file not found"
                else
                    raise SubcommandFailed.new(target, command.join(" "), logname, 0), "something unexpected happened"
                end
            end

            childpid, childstatus = Process.wait2(pid)
            childstatus
        end

        if status.exitstatus > 0
            raise SubcommandFailed.new(target, command.join(" "), logname, status.exitstatus)
        end
    end
end

