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

    @transparent_mode = false

    def self.transparent_mode?
        @transparent_mode
    end

    def self.transparent_mode=(flag)
        @transparent_mode = flag
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
    def self.run(target, phase, *command, &output_filter)
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

        target_name, target_type = target_argument_to_name_and_type(target)

        logdir = if target.respond_to?(:logdir)
                     target.logdir
                 else
                     Autobuild.logdir
                 end

        if target.respond_to?(:working_directory)
            options[:working_directory] ||= target.working_directory
        end

        env = options[:env].dup
        if options[:env_inherit]
            ENV.each do |k, v|
                env[k] = v unless env.key?(k)
            end
        end

        if Autobuild.windows?
            windows_support(options, command)
            return
        end

        logname = compute_log_path(target_name, phase, logdir)

        status, subcommand_output = open_logfile(logname) do |logfile|
            logfile_header(logfile, command, env)

            if Autobuild.verbose
                Autobuild.message "#{target_name}: running #{command.join(' ')}\n"\
                    "    (output goes to #{logname})"
            end

            unless input_streams.empty?
                stdin_r, stdin_w = IO.pipe # to feed subprocess stdin
            end

            out_r, out_w = IO.pipe
            out_r.sync = true
            out_w.sync = true

            logfile.puts "Spawning"
            stdin_redir = { :in => stdin_r } if stdin_r
            begin
                pid = spawn(
                    env, *command,
                    {
                        :chdir => options[:working_directory] || Dir.pwd,
                        :close_others => false,
                        %I[err out] => out_w
                    }.merge(stdin_redir || {})
                )
                logfile.puts "Spawned, PID=#{pid}"
            rescue Errno::ENOENT
                raise Failed.new(nil, false), "command '#{command.first}' not found"
            end

            if Autobuild.nice
                Process.setpriority(Process::PRIO_PROCESS, pid, Autobuild.nice)
            end

            # Feed the input
            unless input_streams.empty?
                logfile.puts "Feeding STDIN"
                stdin_r.close
                readbuffer = feed_input(input_streams, out_r, stdin_w)
                stdin_w.close
            end

            # If the caller asked for process output, provide it to him
            # line-by-line.
            out_w.close

            unless input_streams.empty?
                readbuffer.write(out_r.read)
                readbuffer.seek(0)
                out_r.close
                out_r = readbuffer
            end

            transparent_prefix =
                transparent_output_prefix(target_name, phase, target_type)
            logfile.puts "Processing command output"
            subcommand_output = process_output(
                out_r, logfile, transparent_prefix, options[:encoding], &output_filter
            )
            out_r.close

            logfile.puts "Waiting for #{pid} to finish"
            _, childstatus = Process.wait2(pid)
            logfile.puts "Exit: #{childstatus}"
            [childstatus, subcommand_output]
        end

        handle_exit_status(status, command)
        update_stats(target, phase, start_time)

        subcommand_output
    rescue Failed => e
        error = Autobuild::SubcommandFailed.new(
            target, command.join(" "), logname, e.status, subcommand_output || []
        )
        error.retry = if e.retry?.nil? then options[:retry]
                      else
                          e.retry?
                      end
        error.phase = phase
        raise error, e.message
    end

    def self.update_stats(target, phase, start_time)
        duration = Time.now - start_time
        target_name, = target_argument_to_name_and_type(target)
        Autobuild.add_stat(target, phase, duration)
        FileUtils.mkdir_p(Autobuild.logdir)
        File.open(File.join(Autobuild.logdir, "stats.log"), 'a') do |io|
            formatted_msec = format('%.03i', start_time.tv_usec / 1000)
            formatted_time = "#{start_time.strftime('%F %H:%M:%S')}.#{formatted_msec}"
            io.puts "#{formatted_time} #{target_name} #{phase} #{duration}"
        end
        target.add_stat(phase, duration) if target.respond_to?(:add_stat)
    end

    def self.target_argument_to_name_and_type(target)
        if target.respond_to?(:name)
            [target.name, target.class]
        else
            [target.to_str, nil]
        end
    end

    def self.target_argument_to_name(target)
        if target.respond_to?(:name)
            target.name
        else
            target.to_str
        end
    end

    def self.target_argument_to_type(target, type)
        return type if type

        target.class if target.respond_to?(:name)
    end

    def self.handle_exit_status(status, command)
        return if status.exitstatus == 0

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

    def self.windows_support(options, command)
        Dir.chdir(options[:working_directory]) do
            unless system(*command)
                exit_code = $CHILD_STATUS.exitstatus
                raise Failed.new(exit_code, nil),
                      "'#{command.join(' ')}' returned status #{exit_code}"
            end
        end
    end

    def self.compute_log_path(target_name, phase, logdir)
        File.join(logdir, "#{target_name.gsub(/:/, '_')}-"\
            "#{phase.to_s.gsub(/:/, '_')}.log")
    end

    def self.open_logfile(logname, &block)
        open_flag = if Autobuild.keep_oldlogs then 'a'
                    elsif Autobuild.registered_logfile?(logname) then 'a'
                    else
                        'w'
                    end
        open_flag << ":BINARY"

        unless File.directory?(File.dirname(logname))
            FileUtils.mkdir_p File.dirname(logname)
        end

        Autobuild.register_logfile(logname)
        File.open(logname, open_flag, &block)
    end

    def self.logfile_header(logfile, command, env)
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
    end

    def self.outpipe_each_line(out_r)
        buffer = +""
        while (data = out_r.readpartial(1024))
            buffer << data
            scanner = StringScanner.new(buffer)
            while (line = scanner.scan_until(/\n/))
                yield line
            end
            buffer = scanner.rest.dup
        end
    rescue EOFError
        scanner = StringScanner.new(buffer)
        while (line = scanner.scan_until(/\n/))
            yield line
        end
        yield scanner.rest unless scanner.rest.empty?
    end

    def self.process_output(
        out_r, logfile, transparent_prefix, encoding, &filter
    )
        subcommand_output = []
        outpipe_each_line(out_r) do |line|
            line.force_encoding(encoding)
            line = line.chomp
            subcommand_output << line

            logfile.puts line

            if Autobuild.verbose || transparent_mode?
                STDOUT.puts "#{transparent_prefix}#{line}"
            elsif filter
                # Do not yield
                # would mix the progress output with the actual command
                # output. Assume that if the user wants the command output,
                # the autobuild progress output is unnecessary
                filter.call(line)
            end
        end
        subcommand_output
    end

    def self.transparent_output_prefix(target_name, phase, target_type)
        prefix = "#{target_name}:#{phase}: "
        return prefix unless target_type

        "#{target_type}:#{prefix}"
    end

    def self.feed_input(input_streams, out_r, stdin_w)
        readbuffer = StringIO.new
        input_streams.each do |instream|
            instream.each_line do |line|
                # Read the process output to avoid having it block on a full pipe
                begin
                    loop do
                        readbuffer.write(out_r.read_nonblock(1024))
                    end
                rescue IO::WaitReadable # rubocop:disable Lint/SuppressedException
                end

                stdin_w.write(line)
            end
        end
        readbuffer
    rescue Errno::ENOENT => e
        raise Failed.new(nil, false),
              "cannot open input files: #{e.message}", retry: false
    end
end
