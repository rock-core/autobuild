module Autobuild
    # Management of the progress display
    class ProgressDisplay
        def initialize(io, color: ::Autobuild.method(:color))
            @io = io
            @cursor = TTY::Cursor
            @last_formatted_progress = []
            @progress_messages = []

            @silent = false
            @color = color
            @progress_enabled = true
            @display_lock = Mutex.new
        end

        attr_writer :silent

        def silent?
            @silent
        end

        def silent
            silent = @silent
            @silent = true
            yield
        ensure
            @silent = silent
        end

        attr_writer :progress_enabled

        def progress_enabled?
            !@silent && @progress_enabled
        end

        def message(message, *args, io: @io, force: false)
            return if silent? && !force

            io = args.pop if args.last.respond_to?(:to_io)

            @display_lock.synchronize do
                io.print "#{@cursor.column(1)}#{@cursor.clear_screen_down}"\
                    "#{@color.call(message, *args)}\n"
                io.flush if @io != io
                display_progress
                @io.flush
            end
        end

        def progress_start(key, *args, done_message: nil)
            progress_done(key)

            formatted_message = @color.call(*args)
            @progress_messages << [key, formatted_message]
            if progress_enabled?
                @display_lock.synchronize do
                    display_progress
                end
            else
                message "  #{formatted_message}"
            end

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
            @display_lock.synchronize do
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
                display_progress
            end
        end

        def progress_done(key, display_last = true, message: nil)
            changed = @display_lock.synchronize do
                current_size = @progress_messages.size
                @progress_messages.delete_if do |msg_key, msg|
                    if msg_key == key
                        message = msg if display_last && !message
                        true
                    end
                end
                current_size != @progress_messages.size
            end

            if changed
                if message
                    message("  #{message}")
                    # Note: message calls display_progress already
                else
                    @display_lock.synchronize do
                        display_progress
                    end
                end
                true
            end
        end

        def display_progress
            return unless progress_enabled?

            formatted = format_grouped_messages(@progress_messages.map(&:last),
                indent: "  ")
            @io.print @cursor.clear_screen_down
            @io.print formatted.join("\n")
            if formatted.size > 1
                @io.print "#{@cursor.up(formatted.size - 1)}#{@cursor.column(0)}"
            else
                @io.print @cursor.column(0)
            end
            @io.flush
        end

        def find_common_prefix(msg, other_msg)
            msg = msg.split(" ")
            other_msg = other_msg.split(" ")
            msg.each_with_index do |token, idx|
                if other_msg[idx] != token
                    prefix = msg[0..(idx - 1)].join(" ")
                    prefix << " " unless prefix.empty?
                    return prefix
                end
            end
            msg.join(" ")
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
                        else break
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
                    if lines.last.size + margin + msg.size > width
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
