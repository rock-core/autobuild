module Autobuild
    # Management of the progress display
    class ProgressDisplay
        def initialize(io, color: ::Autobuild.method(:color))
            @io = io
            #@cursor = Blank.new
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
            @silent, silent = true, @silent
            yield
        ensure
            @silent = silent
        end

        attr_writer :progress_enabled

        def progress_enabled?
            !@silent && @progress_enabled
        end

        def message(message, *args, io: @io)
            return if silent?

            if args.last.respond_to?(:to_io)
                io = args.pop
            end

            @display_lock.synchronize do
                io.print "#{@cursor.clear_line}#{@color.call(message, *args)}\n"
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
                        if display_last && !message
                            message = msg
                        end
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
            
            formatted = format_grouped_messages(@progress_messages.map(&:last), indent: "  ")
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
                    if !prefix.empty?
                        prefix << " "
                    end
                    return prefix
                end
            end
            return msg.join(" ")
        end

        def group_messages(messages)
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

            groups.map do |prefix, indexes|
                indexes = indexes.to_a
                next if indexes.empty?
                range = (prefix.size)..-1
                [prefix, indexes.map { |i| messages[i][range] }]
            end.compact
        end

        def format_grouped_messages(messages, indent: "  ")
            terminal_w = TTY::Screen.width
            groups = group_messages(messages)
            groups.each_with_object([]) do |(prefix, messages), lines|
                if prefix.empty?
                    lines << "#{indent}#{messages.shift}"
                else
                    lines << "#{indent}#{prefix.dup.strip} #{messages.shift}"
                end
                until messages.empty?
                    msg = messages.shift.strip
                    if lines.last.size + 2 + msg.size > terminal_w
                        lines << "#{indent}  #{msg}"
                    else
                        lines.last << ", #{msg}"
                    end
                end
                lines
            end
        end
    end
end

