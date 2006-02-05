require 'autobuild/reporting'

module Autobuild::Subprocess
    @@nice = 0
    def self.nice=(value)
        @@nice = value
    end

    class Failed < Exception
        attr_reader :status
        def initialize(status = 0)
            @status = status
        end
    end

    CONTROL_COMMAND_NOT_FOUND = 1
    CONTROL_UNEXPECTED = 2
    def self.run(target, phase, *command)
        # Filter nil and empty? in command
        command.reject!  { |o| o.nil? || (o.respond_to?(:empty?) && o.empty?) }
        command.collect! { |o| o.to_s }

        FileUtils.mkdir_p Autobuild.logdir unless File.directory?(Autobuild.logdir)
        logname = "#{Autobuild.logdir}/#{target}-#{phase}.log"

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
                    if Autobuild.verbose
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
                raise Failed.new, "cannot open input files: #{e.message}"
            end
            pwrite.close

            # Get control status
            cwrite.close
            value = cread.read(4)
            if value
                # An error occured
                value = value.unpack('I').first
                if value == CONTROL_COMMAND_NOT_FOUND
                    raise Failed.new, "file not found"
                else
                    raise Failed.new, "something unexpected happened"
                end
            end

            childpid, childstatus = Process.wait2(pid)
            childstatus
        end

        if status.exitstatus > 0
            raise Failed.new(status.exitstatus), "command returned with status #{status.exitstatus}"
        end

    rescue Failed => e
        error = SubcommandFailed.new(target, command.join(" "), logname, e.status)
        error.phase = phase
        raise error, e.message
    end

end

