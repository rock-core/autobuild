require 'autobuild/exceptions'
module Autobuild
    class << self
        attr_reader :display_lock
        def silent?
            @silent
        end
        attr_writer :silent
    end
    @display_lock = Mutex.new
    @silent = false

    def self.silent
        Autobuild.silent, silent = true, Autobuild.silent?
        yield
    ensure
        Autobuild.silent = silent
    end

    def self.progress_display_enabled?
        @progress_display_enabled
    end

    def self.progress_display_enabled=(value)
        @progress_display_enabled = value
    end

    @progress_display_enabled = true
    @last_progress_msg = nil

    def self.message(*args)
        return if silent?
        display_lock.synchronize do
            display_message(*args)
        end
    end

    def self.display_message(*args)
        io = STDOUT
        if args.last.kind_of?(IO)
            io = args.pop
        end
        msg =
            if args.empty? then ""
            else "#{color(*args)}"
            end

        if !Autobuild.progress_display_enabled?
            if !silent?
                io.puts msg
            end
            return
        end

        if !silent?
            io.puts "#{clear_line}#{msg}"
            if @last_progress_msg
                io.print @last_progress_msg
            end
        end
    end

    class << self
        attr_reader :progress_messages
    end
    @progress_messages = Array.new

    # Displays an error message
    def self.error(message = "")
        message("  ERROR: #{message}", :red, :bold, STDERR)
    end

    # Displays a warning message
    def self.warn(message = "", *style)
        message("  WARN: #{message}", :magenta, *style, STDERR)
    end

    # @return [Boolean] true if there is some progress messages for the given
    #   key
    def self.has_progress_for?(key)
        progress_messages.any? { |msg_key, _| msg_key == key }
    end

    def self.clear_line
        "\e[2K\e[1G"
    end

    def self.progress_start(key, *args)
        if args.last.kind_of?(Hash)
            options = Kernel.validate_options args.pop, :done_message => nil
        else
            options = Hash.new
        end

        progress_done(key)
        display_lock.synchronize do
            progress_messages << [key, color(*args)]
            if Autobuild.progress_display_enabled?
                display_progress
            else
                display_message("  " + color(*args))
            end
        end

        if block_given?
            begin
                result = yield
                if options[:done_message] && has_progress_for?(key)
                    progress(key, *options[:done_message])
                end
                progress_done(key, true)
                result
            rescue Exception
                progress_done(key, false)
                raise
            end
        end
    end
    def self.progress(key, *args)
        found = false
        display_lock.synchronize do
            progress_messages.map! do |msg_key, msg|
                if msg_key == key
                    found = true
                    [msg_key, color(*args)]
                else
                    [msg_key, msg]
                end
            end
            if !found
                progress_messages << [key, color(*args)]
            end

            return if !Autobuild.progress_display_enabled?

            display_progress
        end
    end

    def self.progress_done(key, display_last = true)
        found = false
        display_lock.synchronize do
            last_msg = nil
            progress_messages.delete_if do |msg_key, msg|
                if msg_key == key
                    found = true
                    last_msg = msg
                end
            end
            if found
                if display_last
                    display_message("  #{last_msg}")
                end
                if @last_progress_msg
                    display_progress
                end
            end
        end
        found
    end

    def self.find_common_prefix(msg, other_msg)
        msg = msg.split(" ")
        other_msg = other_msg.split(" ")
        msg.each_with_index do |token, idx|
            if other_msg[idx] != token
                prefix = msg[0..(idx - 1)].join(" ")
                if !prefix.empty?
                    prefix << " "
                end
                return prefix
            end
        end
        return msg.join(" ")
    end

    def self.format_progress_message(messages)
        messages = messages.sort

        groups = Array.new
        groups << ["", (0...messages.size)]
        messages.each_with_index do |msg, idx|
            prefix, grouping = nil, false
            messages[(idx + 1)..-1].each_with_index do |other_msg, other_idx|
                other_idx += idx + 1
                prefix ||= find_common_prefix(msg, other_msg)
                break if !other_msg.start_with?(prefix)

                if grouping
                    break if prefix != groups.last[0]
                    groups.last[1] << other_idx
                else
                    current_prefix, current_group = groups.last
                    if prefix.size > current_prefix.size # create a new group from there
                        groups.last[1] = (current_group.first..[idx-1,current_group.last].min)
                        groups << [prefix, [idx, other_idx]]
                        grouping = true
                    else break
                    end
                end
            end
        end
        if groups.last.last.last < messages.size
            groups << ["", (groups.last.last.last + 1)...(messages.size)]
        end

        result = []
        groups.each do |prefix, indexes|
            if prefix.empty?
                indexes.each do |index|
                    result << messages[index]
                end
            else
                grouped_messages = []
                indexes.each do |index|
                    grouped_messages << messages[index][(prefix.size)..-1]
                end
                if !grouped_messages.empty?
                    result << "#{prefix}#{grouped_messages.uniq.join(", ")}"
                end
            end
        end
        result.join(" | ")
    end

    def self.display_progress
        msg = format_progress_message(progress_messages.map(&:last))

        if msg.empty?
            @last_progress_msg = nil
        else
            msg = "  #{msg}"
            @last_progress_msg = msg
        end

        if !silent?
            if Autobuild.progress_display_enabled?
                print "#{clear_line}#{msg}"
            elsif @last_progress_msg
                puts msg
            end
        end
    end

    ## The reporting module provides the framework # to run commands in
    # autobuild and report errors # to the user
    #
    # It does not use a logging framework like Log4r, but it should ;-)
    module Reporting
        @@reporters = Array.new

        ## Run a block and report known exception
        # If an exception is fatal, the program is terminated using exit()
        def self.report(on_package_failures: default_report_on_package_failures)
            begin yield
            rescue Interrupt => e
                interrupted = e
            rescue Autobuild::Exception => e
                return report_finish_on_error([e], on_package_failures: on_package_failures, interrupted_by: interrupted)
            end

            # If ignore_erorrs is true, check if some packages have failed
            # on the way. If so, raise an exception to inform the user about
            # it
            errors = []
            Autobuild::Package.each do |name, pkg|
                errors.concat(pkg.failures)
            end

            report_finish_on_error(errors, on_package_failures: on_package_failures, interrupted_by: interrupted)
        end

        # @api private
        #
        # Helper that returns the default for on_package_failures
        #
        # The result depends on the value for Autobuild.debug. It is either
        # :exit if debug is false, or :raise if it is true
        def self.default_report_on_package_failures
            if Autobuild.debug then :raise
            else :exit
            end
        end

        # @api private
        #
        # Handle how Reporting.report is meant to finish in case of error(s)
        #
        # @param [Symbol] on_package_failures how does the reporting should behave.
        #
        def self.report_finish_on_error(errors, on_package_failures: default_report_on_package_failures, interrupted_by: nil)
            if ![:raise, :report_silent, :exit_silent].include?(on_package_failures)
                errors.each { |e| error(e) }
            end
            fatal = errors.any?(&:fatal?)
            if !fatal
                if interrupted_by
                    raise interrupted_by
                else
                    return errors
                end
            end

            if on_package_failures == :raise
                if interrupted_by
                    raise interrupted_by
                end

                e = if errors.size == 1 then errors.first
                else CompositeException.new(errors)
                end
                raise e
            elsif [:report_silent, :report].include?(on_package_failures)
                if interrupted_by
                    raise interrupted_by
                else
                    return errors
                end
            elsif [:exit, :exit_silent].include?(on_package_failures)
                exit 1
            else
                raise ArgumentError, "unexpected value for on_package_failures: #{on_package_failures}"
            end
        end

        ## Reports a successful build to the user
        def self.success
            each_reporter { |rep| rep.success }
        end

        ## Reports that the build failed to the user
        def self.error(error)
            each_reporter { |rep| rep.error(error) }
        end

        ## Add a new reporter
        def self.<<(reporter)
            @@reporters << reporter
        end

        def self.remove(reporter)
            @@reporters.delete(reporter)
        end

        def self.clear_reporters
            @@reporters.clear
        end

        def self.each_reporter(&iter)
            @@reporters.each(&iter)
        end

        ## Iterate on all log files
        def self.each_log(&block)
            Autobuild.logfiles.each(&block)
        end
    end

    ## Base class for reporters
    class Reporter
        def error(error); end
        def success; end
    end

    ## Display using stdout
    class StdoutReporter < Reporter
        def error(error)
            STDERR.puts "Build failed: #{error}"
        end
        def success
            puts "Build finished successfully at #{Time.now}"
            if Autobuild.post_success_message
                puts Autobuild.post_success_message
            end
        end
    end
end
