require 'set'
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

    def self.statistics
        @statistics
    end
    def self.reset_statistics
        @statistics = Hash.new
    end
    def self.add_stat(package, phase, duration)
        if !@statistics[package]
            @statistics[package] = { phase => duration }
        elsif !@statistics[package][phase]
            @statistics[package][phase] = duration
        else
            @statistics[package][phase] += duration
        end
    end
    reset_statistics

    @parallel_build_level = nil
    @displayed_error_line_count = 10
    class << self
        # Sets the level of parallelism during the build
        #
        # See #parallel_build_level for detailed information
        attr_writer :parallel_build_level
        
        # set/get a value how much log lines should be displayed on errors
        # this may be an integer or 'ALL' (which will be translated to -1) 
        # this is not using an attr_accessor to be able to validate the values
        def displayed_error_line_count=(value)
            @displayed_error_line_count = validate_displayed_error_line_count(value)
        end
        def displayed_error_line_count
            @displayed_error_line_count
        end

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
		
        if File.file?('/proc/cpuinfo')
            cpuinfo = File.readlines('/proc/cpuinfo')
            physical_ids, core_count, processor_ids = [], [], []
            cpuinfo.each do |line|
                case line
                when /^processor\s+:\s+(\d+)$/
                    processor_ids << Integer($1)
                when /^physical id\s+:\s+(\d+)$/
                    physical_ids << Integer($1)
                when /^cpu cores\s+:\s+(\d+)$/
                    core_count << Integer($1)
                end
            end
            
            # Try to count the number of physical cores, not the number of
            # logical ones. If the info is not available, fallback to the
            # logical count
            if (physical_ids.size == core_count.size) && (physical_ids.size == processor_ids.size)
                info = Array.new
                while (id = physical_ids.shift)
                    info[id] = core_count.shift
                end
                @processor_count = info.compact.inject(&:+)
            else
                @processor_count = processor_ids.size
            end
        else
            result = Open3.popen3("sysctl", "-n", "hw.ncpu") do |_, io, _|
                io.read
            end
            if !result.empty?
                @processor_count = Integer(result.chomp.strip)
            end
        end

        # The format of the cpuinfo file is ... let's say not very standardized.
        # If the cpuinfo detection fails, inform the user and set it to 1
        if !@processor_count
            # Hug... What kind of system is it ?
            Autobuild.message "INFO: cannot autodetect the number of CPUs on this sytem"
            Autobuild.message "INFO: turning parallel builds off"
            Autobuild.message "INFO: you can manually set the number of parallel build processes to N"
            Autobuild.message "INFO: (and therefore turn this message off)"
            Autobuild.message "INFO: with"
            Autobuild.message "    Autobuild.parallel_build_level = N"
            @processor_count = 1
        end

        @processor_count
    end
    
    def self.validate_displayed_error_line_count(lines) 
        if lines == 'ALL'
            return Float::INFINITY
        elsif lines.to_i > 0
            return lines.to_i
        end
        raise ConfigError, 'Autobuild.displayed_error_line_count can only be a positive integer or \'ALL\'' 
    end

end


module Autobuild::Subprocess
    class Failed < Exception
        def retry?; @retry end
        attr_reader :status

        def initialize(status, do_retry)
            @status = status
            @retry = do_retry
        end
    end

    CONTROL_COMMAND_NOT_FOUND = 1
    CONTROL_UNEXPECTED = 2
    CONTROL_INTERRUPT = 3
    def self.run(target, phase, *command)
        STDOUT.sync = true

        input_streams = []
        options = Hash[retry: false]
        if command.last.kind_of?(Hash)
            options = command.pop
            options = Kernel.validate_options options,
                input: nil, working_directory: nil, retry: false
            if options[:input]
                input_streams = [options[:input]]
            end
        end

        start_time = Time.now

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

        if target.respond_to?(:working_directory)
            options[:working_directory] ||= target.working_directory
        end

		logname = File.join(logdir, "#{target_name.gsub(/[:]/,'_')}-#{phase.to_s.gsub(/[:]/,'_')}.log")
        if !File.directory?(File.dirname(logname))
            FileUtils.mkdir_p File.dirname(logname)
        end

	if Autobuild.verbose
	    Autobuild.message "#{target_name}: running #{command.join(" ")}\n    (output goes to #{logname})"
	end

        open_flag = if Autobuild.keep_oldlogs then 'a'
                    elsif Autobuild.registered_logfile?(logname) then 'a'
                    else 'w'
                    end
        if defined? Encoding
            open_flag << ":BINARY"
        end

        Autobuild.register_logfile(logname)
        subcommand_output = Array.new

        status = File.open(logname, open_flag) do |logfile|
            if Autobuild.keep_oldlogs
                logfile.puts
            end
            logfile.puts
            logfile.puts "#{Time.now}: running"
            logfile.puts "    #{command.join(" ")}"
	    logfile.puts "with environment:"
            ENV.keys.sort.each do |key|
                logfile.puts "  '#{key}'='#{ENV[key]}'"
            end
            logfile.puts
            logfile.puts "#{Time.now}: running"
            logfile.puts "    #{command.join(" ")}"
	    logfile.flush
            logfile.sync = true

            if !input_streams.empty?
                pread, pwrite = IO.pipe # to feed subprocess stdin 
            end

            outread, outwrite = IO.pipe
            outread.sync = true
            outwrite.sync = true

            cread, cwrite = IO.pipe # to control that exec goes well

            if Autobuild.windows?
                Dir.chdir(options[:working_directory]) do
                    if !system(*command)
                        raise Failed.new($?.exitstatus, nil),
                            "'#{command.join(' ')}' returned status #{status.exitstatus}"
                    end
                end
                return
            end

            cwrite.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)

            pid = fork do
                begin
                    if options[:working_directory] && (options[:working_directory] != Dir.pwd)
                        Dir.chdir(options[:working_directory])
                    end
                    logfile.puts "in directory #{Dir.pwd}"

                    cwrite.sync = true
                    if Autobuild.nice
                        Process.setpriority(Process::PRIO_PROCESS, 0, Autobuild.nice)
                    end

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
                   
                    if RUBY_VERSION >= "1.9"
                        command << Hash[:close_others => false]
                    end
                    exec(*command)
                rescue Errno::ENOENT
                    cwrite.write([CONTROL_COMMAND_NOT_FOUND].pack('I'))
                    exit(100)
                rescue Interrupt
                    cwrite.write([CONTROL_INTERRUPT].pack('I'))
                    exit(100)
                rescue ::Exception
                    cwrite.write([CONTROL_UNEXPECTED].pack('I'))
                    exit(100)
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
                    raise Failed.new(nil, false),
                        "cannot open input files: #{e.message}", retry: false
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
                    raise Failed.new(nil, false),
                        "command '#{command.first}' not found"
                elsif value == CONTROL_INTERRUPT
                    raise Interrupt, "command '#{command.first}': interrupted by user"
                else
                    raise Failed.new(nil, false),
                        "something unexpected happened"
                end
            end

            # If the caller asked for process output, provide it to him
            # line-by-line.
            outwrite.close
            outread.each_line do |line|
                if line.respond_to?(:force_encoding)
                    line.force_encoding('BINARY')
                end
                if Autobuild.verbose
                    STDOUT.print line
                end
                logfile.puts line
                # Do not yield the line if Autobuild.verbose is true, as it
                # would mix the progress output with the actual command
                # output. Assume that if the user wants the command output,
                # the autobuild progress output is unnecessary
                if !Autobuild.verbose && block_given?
                    yield(line)
                end

                subcommand_output << line
            end
            outread.close

            childpid, childstatus = Process.wait2(pid)
            childstatus
        end

        if !status.exitstatus || status.exitstatus > 0
            raise Failed.new(status.exitstatus, nil),
                "'#{command.join(' ')}' returned status #{status.exitstatus}"
        end

        duration = Time.now - start_time
        Autobuild.add_stat(target, phase, duration)
        FileUtils.mkdir_p(Autobuild.logdir)
        File.open(File.join(Autobuild.logdir, "stats.log"), 'a') do |io|
            formatted_time = "#{start_time.strftime('%F %H:%M:%S')}.#{'%.03i' % [start_time.tv_usec / 1000]}"
            io.puts "#{formatted_time} #{target_name} #{phase} #{duration}"
        end
        if target.respond_to?(:add_stat)
            target.add_stat(phase, duration)
        end
        subcommand_output

    rescue Failed => e
        error = Autobuild::SubcommandFailed.new(target, command.join(" "), logname, e.status)
        error.retry = if e.retry?.nil? then options[:retry]
                      else e.retry?
                      end
        error.phase = phase
        raise error, e.message
    end

end

