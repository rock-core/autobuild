module Autobuild
    @colorizer = Pastel.new
    class << self
        def color=(flag)
            @colorizer =
                if flag.nil?
                    Pastel.new
                else
                    Pastel.new(enabled: flag)
                end
        end

        def color?
            @colorizer.enabled?
        end

        def color(message, *style)
            @colorizer.decorate(message, *style)
        end
    end
end

require 'tty/cursor'
require 'tty/screen'
require 'autobuild/progress_display'

module Autobuild
    class << self
        def silent?
            @display.silent?
        end

        def silent=(flag)
            @display.silent = flag
        end
    end
    @display = ProgressDisplay.new(STDOUT)

    def self.silent(&block)
        @display.silent(&block)
    end

    def self.progress_display_enabled?
        @display.progress_enabled?
    end

    def self.progress_display_synchronize(&block)
        @display.synchronize(&block)
    end

    # @deprecated use {progress_display_mode=} instead
    def self.progress_display_enabled=(value)
        @display.progress_enabled = value
    end

    def self.progress_display_mode=(value)
        @display.progress_mode = value
    end

    def self.progress_display_period=(value)
        @display.progress_period = value
    end

    def self.message(*args, **options)
        @display.message(*args, **options)
    end

    # Displays an error message
    def self.error(message = "")
        message("  ERROR: #{message}", :red, :bold, io: STDERR)
    end

    # Displays a warning message
    def self.warn(message = "", *style)
        message("  WARN: #{message}", :magenta, *style, io: STDERR)
    end

    def self.progress_start(key, *args, **options, &block)
        @display.progress_start(key, *args, **options, &block)
    end

    def self.progress(key, *args)
        @display.progress(key, *args)
    end

    def self.progress_done(key, display_last = true, message: nil)
        @display.progress_done(key, display_last, message: message)
    end

    ## The reporting module provides the framework # to run commands in
    # autobuild and report errors # to the user
    #
    # It does not use a logging framework like Log4r, but it should ;-)
    module Reporting
        @reporters = Array.new

        ## Run a block and report known exception
        # If an exception is fatal, the program is terminated using exit()
        def self.report(on_package_failures: default_report_on_package_failures)
            begin yield
            rescue Interrupt => e
                interrupted = e
            rescue Autobuild::Exception => e
                return report_finish_on_error([e],
                                              on_package_failures: on_package_failures,
                                              interrupted_by: interrupted)
            end

            # If ignore_erorrs is true, check if some packages have failed
            # on the way. If so, raise an exception to inform the user about
            # it
            errors = []
            Autobuild::Package.each do |_name, pkg|
                errors.concat(pkg.failures)
            end

            report_finish_on_error(errors,
                                   on_package_failures: on_package_failures,
                                   interrupted_by: interrupted)
        end

        # @api private
        #
        # Helper that returns the default for on_package_failures
        #
        # The result depends on the value for Autobuild.debug. It is either
        # :exit if debug is false, or :raise if it is true
        def self.default_report_on_package_failures
            if Autobuild.debug then :raise
            else
                :exit
            end
        end

        # @api private
        #
        # Handle how Reporting.report is meant to finish in case of error(s)
        #
        # @param [Symbol] on_package_failures how does the reporting should behave.
        #
        def self.report_finish_on_error(errors,
            on_package_failures: default_report_on_package_failures, interrupted_by: nil)
            if (not_package_error = errors.find { |e| !e.respond_to?(:fatal?) })
                raise not_package_error
            end

            unless %i[raise report_silent exit_silent].include?(on_package_failures)
                errors.each { |e| error(e) }
            end

            fatal = errors.any?(&:fatal?)
            unless fatal
                if interrupted_by
                    raise interrupted_by
                else
                    return errors
                end
            end

            if on_package_failures == :raise
                raise interrupted_by if interrupted_by

                e = if errors.size == 1 then errors.first
                    else
                        CompositeException.new(errors)
                    end
                raise e
            elsif %i[report_silent report].include?(on_package_failures)
                if interrupted_by
                    raise interrupted_by
                else
                    errors
                end
            elsif %i[exit exit_silent].include?(on_package_failures)
                exit 1
            else
                raise ArgumentError, "unexpected value for on_package_failures: "\
                    "#{on_package_failures}"
            end
        end

        ## Reports a successful build to the user
        def self.success
            each_reporter(&:success)
        end

        ## Reports that the build failed to the user
        def self.error(error)
            each_reporter { |rep| rep.error(error) }
        end

        ## Add a new reporter
        def self.<<(reporter)
            @reporters << reporter
        end

        def self.remove(reporter)
            @reporters.delete(reporter)
        end

        def self.clear_reporters
            @reporters.clear
        end

        def self.each_reporter(&iter)
            @reporters.each(&iter)
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
            puts Autobuild.post_success_message if Autobuild.post_success_message
        end
    end

    HUMAN_READABLE_SIZES = [
        [1_000_000_000.0, "G"],
        [1_000_000.0, "M"],
        [1_000.0, "k"],
        [1.0, ""]
    ].freeze

    def self.human_readable_size(size)
        HUMAN_READABLE_SIZES.each do |scale, name|
            scaled_size = (size / scale)
            if scaled_size > 1
                return format("%3.1<scaled>f%<scale_name>s",
                              scaled: scaled_size,
                              scale_name: name)
            end
        end
    end
end
