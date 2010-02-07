require 'autobuild/exceptions'
require 'autobuild/reporting'
require 'fcntl'

module Autobuild
    @logfiles = Set.new
    def self.clear_logfiles
        @logfiles.clear
    end

    def self.logfiles
        @logfiles
    end

    def self.register_logfile(path)
        @logfiles << path
    end

    def self.registered_logfile?(logfile)
        @logfiles.include?(logfile)
    end

    @parallel_build_level = nil
    class << self
        # Sets the level of parallelism during the build
        #
        # See #parallel_build_level for detailed information
        attr_writer :parallel_build_level

        # Returns the number of processes that can run in parallel during the
        # build. This is a system-wide value that can be overriden in a
        # per-package fashion by using Package#parallel_build_level.
        #
        # If not set, defaults to the number of CPUs on the system
        #
        # See also #parallel_build_level=
        def parallel_build_level
            if @parallel_build_level.nil?
                # No user-set value, return the count of processors on this
                # machine
                autodetect_processor_count
            elsif !@parallel_build_level || @parallel_build_level <= 0
                1
            else
                @parallel_build_level
            end
        end
    end

    # Returns the number of CPUs present on this system
    def self.autodetect_processor_count
        if @processor_count
            return @processor_count
        end

        if File.file?('/sys/devices/system/cpu/present')
            range = File.read('/sys/devices/system/cpu/present').
                chomp
                
            @processor_count = Integer(range.split('-').last) + 1
        elsif File.file?('/proc/cpuinfo')
            # Just count the numer of processor: \d lines
            @processor_count = File.readlines('/proc/cpuinfo').
                find_all { |l| l =~ /^processor\s+:\s+\d+$/ }.
                count
        else
            # Hug... What kind of system is it ?
            STDERR.puts "INFO: cannot autodetect the number of CPUs on this sytem"
            @processor_count = 1
        end
    end
end


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
        STDOUT.sync = true

        # Filter nil and empty? in command
        command.reject!  { |o| o.nil? || (o.respond_to?(:empty?) && o.empty?) }
        command.collect! { |o| o.to_s }

        target_name = if target.respond_to?(:name)
                          target.name
                      else target.to_str
                      end
        logdir = if target.respond_to?(:logdir)
                     target.logdir
                 else Autobuild.logdir
                 end

        logname = File.join(logdir, "#{target_name}-#{phase}.log")
        if !File.directory?(File.dirname(logname))
            FileUtils.mkdir_p File.dirname(logname)
        end

	if Autobuild.verbose
	    puts "#{target_name}: running #{command.join(" ")}\n    (output goes to #{logname})"
	end

        input_streams = command.collect { |o| $1 if o =~ /^\<(.+)/ }.compact
        command.reject! { |o| o =~ /^\<(.+)/ }

        open_flag = if Autobuild.keep_oldlogs then 'a'
                    elsif Autobuild.registered_logfile?(logname) then 'a'
                    else 'w'
                    end

        Autobuild.register_logfile(logname)

        status = File.open(logname, open_flag) do |logfile|
            if Autobuild.keep_oldlogs
                logfile.puts
            end
            logfile.puts "#{Time.now}: running"
            logfile.puts "    #{command.join(" ")}"
	    logfile.puts
	    logfile.flush
            logfile.sync = true

            if !input_streams.empty?
                pread, pwrite = IO.pipe # to feed subprocess stdin 
            end
            if block_given? # the caller wants the stdout/stderr stream of the process, git it to him
                outread, outwrite = IO.pipe
                outread.sync = true
                outwrite.sync = true
            end
            cread, cwrite = IO.pipe # to control that exec goes well

            cwrite.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)

            pid = fork do
                cwrite.sync = true
                begin
                    Process.setpriority(Process::PRIO_PROCESS, 0, Autobuild.nice)

                    if outwrite
                        outread.close
                        $stderr.reopen(outwrite.dup)
                        $stdout.reopen(outwrite.dup)
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
            if !input_streams.empty?
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
            end

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

            # If the caller asked for process output, provide it to him
            # line-by-line.
            if outread
                outwrite.close
                outread.each_line do |line|
                    if Autobuild.verbose
                        STDOUT.print line
                    end
                    logfile.puts line
                    if block_given?
                        yield(line)
                    end
                end
                outread.close
            end

            childpid, childstatus = Process.wait2(pid)
            childstatus
        end

        if !status.exitstatus || status.exitstatus > 0
            raise Failed.new(status.exitstatus), "'#{command.join(' ')}' returned status #{status.exitstatus}"
        end

    rescue Failed => e
        error = Autobuild::SubcommandFailed.new(target_name, command.join(" "), logname, e.status)
        error.phase = phase
        raise error, e.message
    end

end

