require 'set'
require 'autobuild/exceptions'
require 'autobuild/reporting'
require 'fcntl'
require 'English'

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

        attr_reader :displayed_error_line_count

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
        return @processor_count if @processor_count

        if File.file?('/proc/cpuinfo')
            cpuinfo = File.readlines('/proc/cpuinfo')
            physical_ids  = []
            core_count    = []
            processor_ids = []
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
            has_consistent_info =
                (physical_ids.size == core_count.size) &&
                (physical_ids.size == processor_ids.size)
            if has_consistent_info
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
            @processor_count = Integer(result.chomp.strip) unless result.empty?
        end

        # The format of the cpuinfo file is ... let's say not very standardized.
        # If the cpuinfo detection fails, inform the user and set it to 1
        unless @processor_count
            # Hug... What kind of system is it ?
            Autobuild.message "INFO: cannot autodetect the number of CPUs on this sytem"
            Autobuild.message "INFO: turning parallel builds off"
            Autobuild.message "INFO: you can manually set the number of parallel build "\
                "processes to N"
            Autobuild.message "INFO: (and therefore turn this message off)"
            Autobuild.message "INFO: with"
            Autobuild.message "    Autobuild.parallel_build_level = N"
            @processor_count = 1
        end

        @processor_count
    end

    def self.validate_displayed_error_line_count(lines)
        if lines == 'ALL'
            Float::INFINITY
        elsif lines.to_i > 0
            lines.to_i
        else
            raise ConfigException.new, 'Autobuild.displayed_error_line_count can only "\
                "be a positive integer or \'ALL\''
        end
    end
end

module Autobuild::Subprocess # rubocop:disable Style/ClassAndModuleChildren
    at_exit do
        exit! if forced_exit?
    end

    @forced_exit = false

    def self.forced_exit=(flag)
        @forced_exit = flag
    end

    def self.forced_exit?
        @forced_exit
    end

    class Failed < RuntimeError
        attr_reader :status

        def retry?
            @retry
        end

        def initialize(status, do_retry)
            @status = status
            @retry = do_retry
            super()
        end
    end

    CONTROL_COMMAND_NOT_FOUND = 1
    CONTROL_UNEXPECTED = 2
    CONTROL_INTERRUPT = 3

    @transparent_mode = false

    def self.transparent_mode?
        @transparent_mode
    end

    def self.transparent_mode=(flag)
        @transparent_mode = flag
    end

    def self.workaround_broken_waitpid=(flag)
        @workaround_broken_waitpid = flag
    end

    def self.workaround_broken_waitpid?
        @workaround_broken_waitpid
    end

    def self.waitpid2(pid)
        if workaround_broken_waitpid?
            waitpid2_polling(pid)
        else
            Process.waitpid2(pid)
        end
    end

    def self.waitpid2_polling(pid, period: 0.01)
        display = false
        start_display = Time.now + 1
        loop do
            begin
                display = Time.now > start_display
                if (result = Process.waitpid2(pid, Process::WNOHANG))
                    $stderr.puts "Received result of #{pid}" if display
                    return result
                end

                $stderr.puts "No result for #{pid}, sleeping" if display
                sleep(period)
            rescue Errno::ECHILD
                $stderr.puts "process #{pid} disappeared without letting us reap it"
                break
            end
        end
    end

    # Run a subcommand and return its standard output
    #
    # The command's standard and error outputs, as well as the full command line
    # and an environment dump are saved in a log file in either the valure
    # returned by target#logdir, or Autobuild.logdir if the target does not
    # respond to #logdir.
    #
    # The subprocess priority is controlled by Autobuild.nice
    #
    # @param [String,(#name,#logdir,#working_directory)] target the target we
    #   run the subcommand for. In general, it will be a Package object (run from
    #   Package#run)
    # @param [String] phase in which build phase this subcommand is executed
    # @param [Array<String>] the command itself
    # @yieldparam [String] line if a block is given, each output line from the
    #   command's standard output are yield to it. This is meant for progress
    #   display, and is disabled if Autobuild.verbose is set.
    # @param [Hash] options
    # @option options [String] :working_directory the directory in which the
    #   command should be started. If nil, runs in the current directory. The
    #   default is to either use the value returned by #working_directory on
    #   {target} if it responds to it, or nil.
    # @option options [Boolean] :retry (false) controls whether a failure to
    #   execute this command should be retried by autobuild retry mechanisms (i.e.
    #   in the importers) or not. {run} will not retry the command by itself, it
    #   is passed as a hint for error handling clauses about whether the error
    #   should be retried or not
    # @option options [Array<IO>] :input_streams list of input streams that
    #   should be fed to the command standard input. If a file needs to be given,
    #   the :input argument can be used as well as a shortcut
    # @option options [String] :input the path to a file whose content should be
    #   fed to the command standard input
    # @return [String] the command standard output
    def self.run(target, phase, *command)
        STDOUT.sync = true

        input_streams = []
        options = {
            retry: false, encoding: 'BINARY',
            env: ENV.to_hash, env_inherit: true
        }

        if command.last.kind_of?(Hash)
            options = command.pop
            options = Kernel.validate_options(
                options,
                input: nil, working_directory: nil, retry: false,
                input_streams: [],
                env: ENV.to_hash,
                env_inherit: true,
                encoding: 'BINARY'
            )

            input_streams << File.open(options[:input]) if options[:input]
            input_streams.concat(options[:input_streams]) if options[:input_streams]
        end

        start_time = Time.now

        # Filter nil and empty? in command
        command.reject! { |o| o.nil? || (o.respond_to?(:empty?) && o.empty?) }
        command.collect!(&:to_s)

        if target.respond_to?(:name)
            target_name = target.name
            target_type = target.class
        else
            target_name = target.to_str
            target_type = nil
        end
        logdir = if target.respond_to?(:logdir)
                     target.logdir
                 else
                     Autobuild.logdir
                 end

        if target.respond_to?(:working_directory)
            options[:working_directory] ||= target.working_directory
        end

        logname = File.join(logdir, "#{target_name.gsub(/:/, '_')}-"\
            "#{phase.to_s.gsub(/:/, '_')}.log")
        unless File.directory?(File.dirname(logname))
            FileUtils.mkdir_p File.dirname(logname)
        end

        if Autobuild.verbose
            Autobuild.message "#{target_name}: running #{command.join(' ')}\n"\
                "    (output goes to #{logname})"
        end

        open_flag = if Autobuild.keep_oldlogs then 'a'
                    elsif Autobuild.registered_logfile?(logname) then 'a'
                    else
                        'w'
                    end
        open_flag << ":BINARY"

        Autobuild.register_logfile(logname)
        subcommand_output = Array.new

        env = options[:env].dup
        if options[:env_inherit]
            ENV.each do |k, v|
                env[k] = v unless env.key?(k)
            end
        end

        status = File.open(logname, open_flag) do |logfile|
            logfile.puts if Autobuild.keep_oldlogs
            logfile.puts
            logfile.puts "#{Time.now}: running"
            logfile.puts "    #{command.join(' ')}"
            logfile.puts "with environment:"
            env.keys.sort.each do |key|
                if (value = env[key])
                    logfile.puts "  '#{key}'='#{value}'"
                end
            end
            logfile.puts
            logfile.puts "#{Time.now}: running"
            logfile.puts "    #{command.join(' ')}"
            logfile.flush
            logfile.sync = true

            unless input_streams.empty?
                pread, pwrite = IO.pipe # to feed subprocess stdin
            end

            outread, outwrite = IO.pipe
            outread.sync = true
            outwrite.sync = true

            cread, cwrite = IO.pipe # to control that exec goes well

            if Autobuild.windows?
                Dir.chdir(options[:working_directory]) do
                    unless system(*command)
                        exit_code = $CHILD_STATUS.exitstatus
                        raise Failed.new(exit_code, nil),
                              "'#{command.join(' ')}' returned status #{exit_code}"
                    end
                end
                return # rubocop:disable Lint/NonLocalExitFromIterator
            end

            cwrite.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)

            pid = fork do
                    logfile.puts "in directory #{options[:working_directory] || Dir.pwd}"

                    cwrite.sync = true
                    if Autobuild.nice
                        Process.setpriority(Process::PRIO_PROCESS, 0, Autobuild.nice)
                    end

                    outread.close
                    $stderr.reopen(outwrite.dup)
                    $stdout.reopen(outwrite.dup)

                    unless input_streams.empty?
                        pwrite.close
                        $stdin.reopen(pread)
                    end

                    exec(env, *command,
                         chdir: options[:working_directory] || Dir.pwd,
                         close_others: false)
            rescue Errno::ENOENT
                    cwrite.write([CONTROL_COMMAND_NOT_FOUND].pack('I'))
                    exit(100)
            rescue Interrupt
                    cwrite.write([CONTROL_INTERRUPT].pack('I'))
                    exit(100)
            rescue ::Exception => e
                    STDERR.puts e
                    STDERR.puts e.backtrace.join("\n  ")
                    cwrite.write([CONTROL_UNEXPECTED].pack('I'))
                    exit(100)
            end

            readbuffer = StringIO.new

            # Feed the input
            unless input_streams.empty?
                pread.close
                begin
                    input_streams.each do |instream|
                        instream.each_line do |line|
                            while IO.select([outread], nil, nil, 0)
                                readbuffer.write(outread.readpartial(128))
                            end
                            pwrite.write(line)
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
                value = value.unpack1('I')
                case value
                when CONTROL_COMMAND_NOT_FOUND
                    raise Failed.new(nil, false), "command '#{command.first}' not found"
                when CONTROL_INTERRUPT
                    raise Interrupt, "command '#{command.first}': interrupted by user"
                else
                    raise Failed.new(nil, false), "something unexpected happened"
                end
            end

            transparent_prefix = "#{target_name}:#{phase}: "
            transparent_prefix = "#{target_type}:#{transparent_prefix}" if target_type

            # If the caller asked for process output, provide it to him
            # line-by-line.
            outwrite.close

            unless input_streams.empty?
                readbuffer.write(outread.read)
                readbuffer.seek(0)
                outread.close
                outread = readbuffer
            end

            data_thread = Thread.new do
                outread.each_line do |line|
                    line.force_encoding(options[:encoding])
                    line = line.chomp
                    subcommand_output << line

                    logfile.puts line

                    if Autobuild.verbose || transparent_mode?
                        STDOUT.puts "#{transparent_prefix}#{line}"
                    elsif block_given?
                        # Do not yield
                        # would mix the progress output with the actual command
                        # output. Assume that if the user wants the command output,
                        # the autobuild progress output is unnecessary
                        yield(line)
                    end
                end
                outread.close unless outread.closed?
            rescue IOError
            end

            _, childstatus = Process.waitpid2(pid)
            tic = Time.now
            unless data_thread.join(5)
                STDERR.puts "subprocess #{pid} communication pipe did not close after process finished"
                begin
                    outread.autoclose = false
                rescue IOError # Thread closed the IO first
                end

                unless forced_exit?
                    STDERR.puts "will force process exit"
                    self.forced_exit = true
                end
            end

            logfile.puts "Exit: #{childstatus}"
            childstatus
        end

        if !status
            raise Failed.new(nil, nil),
                  "'#{command.join(' ')}' waitpid() failed"
        end

        if !status.exitstatus || status.exitstatus > 0
            if status.termsig == 2 # SIGINT == 2
                raise Interrupt, "subcommand #{command.join(' ')} interrupted"
            end

            if status.termsig
                raise Failed.new(status.exitstatus, nil),
                      "'#{command.join(' ')}' terminated by signal #{status.termsig}"
            else
                raise Failed.new(status.exitstatus, nil),
                      "'#{command.join(' ')}' returned status #{status.exitstatus}"
            end
        end

        duration = Time.now - start_time
        Autobuild.add_stat(target, phase, duration)
        FileUtils.mkdir_p(Autobuild.logdir)
        File.open(File.join(Autobuild.logdir, "stats.log"), 'a') do |io|
            formatted_msec = format('%.03i', start_time.tv_usec / 1000)
            formatted_time = "#{start_time.strftime('%F %H:%M:%S')}.#{formatted_msec}"
            io.puts "#{formatted_time} #{target_name} #{phase} #{duration}"
        end
        target.add_stat(phase, duration) if target.respond_to?(:add_stat)
        subcommand_output
    rescue Failed => e
        error = Autobuild::SubcommandFailed.new(target, command.join(" "),
                                                logname, e.status, subcommand_output)
        error.retry = if e.retry?.nil? then options[:retry]
                      else
                          e.retry?
                      end
        error.phase = phase
        raise error, e.message
    end
end
