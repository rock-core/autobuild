require 'autobuild/exceptions'
require 'autobuild/reporting'

module Autobuild::Subprocess
    class Failed < Exception
        attr_reader :status
        def initialize(status = nil)
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
        if !File.directory?(File.dirname(logname))
            FileUtils.mkdir_p File.dirname(logname)
        end

	if Autobuild.verbose
	    puts "#{target}: running #{command.join(" ")}\n    (output goes to #{logname})"
	end

        input_streams = command.collect { |o| $1 if o =~ /^\<(.+)/ }.compact
        command.reject! { |o| o =~ /^\<(.+)/ }

        open_flag = if Autobuild.keep_oldlogs then 'a'
                    else 'w'
                    end

        status = File.open(logname, open_flag) do |logfile|
            if Autobuild.keep_oldlogs
                logfile.puts
            end
            logfile.puts "#{Time.now}: running"
            logfile.puts "    #{command.join(" ")}"
	    logfile.puts
	    logfile.flush

            pread, pwrite = IO.pipe # to feed subprocess stdin 
            cread, cwrite = IO.pipe # to control that exec goes well

            pid = fork do
                cwrite.sync = true
                begin
                    Process.setpriority(Process::PRIO_PROCESS, 0, Autobuild.nice)
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
            end

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
                    raise Failed.new, "command '#{command.first}' not found"
                else
                    raise Failed.new, "something unexpected happened"
                end
            end

            childpid, childstatus = Process.wait2(pid)
            childstatus
        end

        if status.exitstatus > 0
            raise Failed.new(status.exitstatus), "'#{command.join(' ')}' returned status #{status.exitstatus}"
        end

    rescue Failed => e
        error = Autobuild::SubcommandFailed.new(target, command.join(" "), logname, e.status)
        error.phase = phase
        raise error, e.message
    end

end

