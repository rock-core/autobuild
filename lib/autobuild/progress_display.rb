require "concurrent/atomic/atomic_boolean"
require "concurrent/array"

module Autobuild
    # Management of the progress display
    class ProgressDisplay
        def initialize(io, color: ::Autobuild.method(:color))
            @io = io
            @cursor = TTY::Cursor
            @last_formatted_progress = []
            @progress_messages = Concurrent::Array.new

            @silent = false
            @color = color
            @display_lock = Mutex.new

            @next_progress_display = Time.at(0)
            @progress_mode = :single_line
            @progress_period = 0.1

            @message_queue = Queue.new
            @forced_progress_display = Concurrent::AtomicBoolean.new(false)
        end

        def synchronize(&block)
            result = @display_lock.synchronize(&block)
            refresh_display
            result
        end

        # Set the minimum time between two progress messages
        #
        # @see period
        def progress_period=(period)
            @progress_period = Float(period)
        end

        # Minimum time between two progress displays
        #
        # This does not affect normal messages
        #
        # @return [Float]
        attr_reader :progress_period

        # Valid progress modes
        #
        # @see progress_mode=
        PROGRESS_MODES = %I[single_line newline off].freeze

        # Sets how progress messages will be displayed
        #
        # @param [String] the new mode. Can be either 'single_line', where a
        #   progress message replaces the last one, 'newline' which displays
        #   each on a new line or 'off' to disable progress messages altogether
        def progress_mode=(mode)
            mode = mode.to_sym
            unless PROGRESS_MODES.include?(mode)
                raise ArgumentError,
                      "#{mode} is not a valid mode, expected one of "\
                      "#{PROGRESS_MODES.join(', ')}"
            end
            @progress_mode = mode
        end

        # Return the current display mode
        #
        # @return [Symbol]
        # @see mode=
        attr_reader :progress_mode

        def silent?
            @silent
        end

        attr_writer :silent

        def silent
            silent = @silent
            @silent = true
            yield
        ensure
            @silent = silent
        end

        # @deprecated use progress_mode= instead
        def progress_enabled=(flag)
            self.progress_mode = flag ? :single_line : :off
        end

        # Whether progress messages will be displayed at all
        def progress_enabled?
            !@silent && (@progress_mode != :off)
        end

        def message(message, *args, io: @io, force: false)
            return if silent? && !force

            io = args.pop if args.last.respond_to?(:to_io)
            @message_queue << [message, args, io]

            refresh_display
        end

        def progress_start(key, *args, done_message: nil)
            progress_done(key)

            formatted_message = @color.call(*args)
            @progress_messages << [key, formatted_message]
            if progress_enabled?
                @forced_progress_display.make_true
            else
                message "  #{formatted_message}"
            end

            refresh_display

            if block_given?
                begin
                    result = yield
                    progress_done(key, message: done_message)
                    result
                rescue Exception
                    progress_done(key)
                    raise
                end
            end
        end

        def progress(key, *args)
            found = false
            @progress_messages.map! do |msg_key, msg|
                if msg_key == key
                    found = true
                    [msg_key, @color.call(*args)]
                else
                    [msg_key, msg]
                end
            end
            @progress_messages << [key, @color.call(*args)] unless found

            refresh_display
        end

        def progress_done(key, display_last = true, message: nil)
            current_size = @progress_messages.size
            @progress_messages.delete_if do |msg_key, msg|
                if msg_key == key
                    message = msg if display_last && !message
                    true
                end
            end
            changed = current_size != @progress_messages.size

            if changed
                if message
                    message("  #{message}")
                    # NOTE: message updates the display already
                else
                    refresh_display
                end
                true
            end
        end

        def refresh_display
            return unless @display_lock.try_lock

            begin
                refresh_display_under_lock
            ensure
                @display_lock.unlock
            end
        end

        def refresh_display_under_lock
            # Display queued messages
            until @message_queue.empty?
                message, args, io = @message_queue.pop
                io.print @cursor.clear_screen_down if @progress_mode == :single_line
                io.puts @color.call(message, *args)

                io.flush if @io != io
            end

            # And re-display the progress
            display_progress(consider_period: @forced_progress_display.false?)
            @forced_progress_display.make_false
            @io.flush
        end

        def display_progress(consider_period: true)
            return unless progress_enabled?
            return if consider_period && (@next_progress_display > Time.now)

            formatted = format_grouped_messages(
                @progress_messages.map(&:last),
                indent: "  "
            )
            if @progress_mode == :newline
                @io.print formatted.join("\n")
                @io.print "\n"
            else
                @io.print @cursor.clear_screen_down
                @io.print formatted.join("\n")
                @io.print @cursor.up(formatted.size - 1) if formatted.size > 1
                @io.print @cursor.column(0)
            end
            @io.flush
            @next_progress_display = Time.now + @progress_period
        end

        def find_common_prefix(msg, other_msg)
            msg = msg.split(' ')
            other_msg = other_msg.split(' ')
            msg.each_with_index do |token, idx|
                if other_msg[idx] != token
                    prefix = msg[0..(idx - 1)].join(" ")
                    prefix << ' ' unless prefix.empty?
                    return prefix
                end
            end
            msg.join(' ')
        end

        def group_messages(messages)
            messages = messages.sort

            groups = Array.new
            groups << ["", (0...messages.size)]
            messages.each_with_index do |msg, idx|
                prefix = nil
                grouping = false
                messages[(idx + 1)..-1].each_with_index do |other_msg, other_idx|
                    other_idx += idx + 1
                    prefix ||= find_common_prefix(msg, other_msg)
                    break unless other_msg.start_with?(prefix)

                    if grouping
                        break if prefix != groups.last[0]

                        groups.last[1] << other_idx
                    else
                        current_prefix, current_group = groups.last
                        if prefix.size > current_prefix.size # create a new group
                            group_end_index = [idx - 1, current_group.last].min
                            groups.last[1] = (current_group.first..group_end_index)
                            groups << [prefix, [idx, other_idx]]
                            grouping = true
                        else
                            break
                        end
                    end
                end
            end
            if groups.last.last.last < messages.size
                groups << ["", (groups.last.last.last + 1)...(messages.size)]
            end

            groups.map do |prefix, indexes|
                indexes = indexes.to_a
                next if indexes.empty?

                range = (prefix.size)..-1
                [prefix, indexes.map { |i| messages[i][range] }]
            end.compact
        end

        def format_grouped_messages(raw_messages, indent: "  ", width: TTY::Screen.width)
            groups = group_messages(raw_messages)
            groups.each_with_object([]) do |(prefix, messages), lines|
                if prefix.empty?
                    lines.concat(messages.map { |m| "#{indent}#{m.strip}" })
                    next
                end

                lines << "#{indent}#{prefix.dup.strip} #{messages.shift}"
                until messages.empty?
                    msg = messages.shift.strip
                    margin = messages.empty? ? 1 : 2
                    if lines.last.size + margin + msg.size + 1 > width
                        lines.last << ","
                        lines << +""
                        lines.last << indent << indent << msg
                    else
                        lines.last << ", " << msg
                    end
                end
                lines.last << "," unless messages.empty?
            end
        end
    end
end
