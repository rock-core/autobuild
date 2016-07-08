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
            io.puts msg
            return
        end

        size =
            if @last_progress_msg then @last_progress_msg.size
            else 0
            end

        if !silent?
            io.puts "\r#{msg}#{" " * [size - msg.size, 0].max}"
            if @last_progress_msg
                print "#{@last_progress_msg}"
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
        return msg
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
                    result << "#{prefix}#{grouped_messages.join(", ")}"
                end
            end
        end
        result.join(" | ")
    end

    def self.display_progress
        msg = format_progress_message(progress_messages.map(&:last))
        last_msg_length =
            if @last_progress_msg then @last_progress_msg.length
            else 0
            end

        if msg.empty?
            blank = " " * last_msg_length
            @last_progress_msg = nil
        else
            msg = "  #{msg}"
            blank = " " * [last_msg_length - msg.length, 0].max
            @last_progress_msg = msg
        end

        if !silent?
            if Autobuild.progress_display_enabled?
                print "\r#{msg}#{blank}"
                print "\r#{msg}"
            elsif @last_progress_msg
                puts msg
            end
        end
    end

    # The exception type that is used to report multiple errors that occured
    # when ignore_errors is set
    class CompositeException < Autobuild::Exception
        # The array of exception objects representing all the errors that
        # occured during the build
        attr_reader :original_errors

        def initialize(original_errors)
            @original_errors = original_errors
        end

        def mail?; true end

        def to_s
            result = ["#{original_errors.size} errors occured"]
            original_errors.each_with_index do |e, i|
                result << "(#{i}) #{e.to_s}"
            end
            result.join("\n")
        end
    end

    ## The reporting module provides the framework
    # to run commands in autobuild and report errors 
    # to the user
    #
    # It does not use a logging framework like Log4r, but it should ;-)
    module Reporting
        @@reporters = Array.new

        ## Run a block and report known exception
        # If an exception is fatal, the program is terminated using exit()
        def self.report
            begin
                yield

                # If ignore_erorrs is true, check if some packages have failed
                # on the way. If so, raise an exception to inform the user about
                # it
                errors = []
                Autobuild::Package.each do |name, pkg|
                    errors.concat(pkg.failures)
                end

                if !errors.empty?
                    raise CompositeException.new(errors)
                end

            rescue Autobuild::Exception => e
                error(e)
                if e.fatal?
                    if Autobuild.debug
                        raise
                    else
                        exit 1
                    end
                end
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

