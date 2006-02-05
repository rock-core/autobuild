require 'optparse'
require 'rake'
require 'singleton'

module Autobuild
    class << self
        %w{ nice srcdir prefix
            verbose debug do_update do_build
            daemonize clean_log }.each do |name|
            attr_accessor name
        end

        attr_reader :programs
        attr_writer :logdir
    end
    DEFAULT_OPTIONS = { :nice => 0,
        :srcdir => nil, :prefix => nil, :logdir => nil,
        :verbose => false, :debug => false, :do_build => true, :do_update => true, 
        :daemonize => false }

    @programs = Hash.new
    DEFAULT_OPTIONS.each do |name, value|
        send("#{name}=", value)
    end

    class << self
        # Configuration for the mail reporter
        def mail(config = nil)
            @mail = config if config
            @mail || {}
        end

        def logdir; @logdir || "#{prefix}/log" end

        def clean_log!
            Reporting.each_log do |file|
                FileUtils.rm_f file
            end
        end

        # Get a given program, using its name as default value
        def tool(name)
            programs[name.to_sym] || programs[name.to_s] || name.to_s
        end

        # Gets autobuild options from the command line
        # and returns the remaining elements
        def commandline(args)
            parser = OptionParser.new do |opts|
                opts.separator "Path specification"
                opts.on("--srcdir PATH", "sources are installed in PATH") do |srcdir| end
                opts.on("--prefix PATH", "built packages are installed in PATH") do |prefix|
                    logdir = "#{prefix}/autobuild"
                end
                opts.on("--logdir PATH", "logs are saved in PATH (default: <prefix>/autobuild)") do |logdir| end

                opts.separator ""
                opts.separator "General behaviour"
                opts.on('--nice NICE', Integer, 'nice the subprocesses to the given value') do |nice| end
                opts.on("--[no-]daemon", "go into daemon mode") do |daemonize| end
                opts.on("--[no-]update", "update already checked-out sources") do |do_update| end
                opts.on("--[no-]build",  "only prepare packages, do not build them") do |do_build| end 

                opts.separator ""
                opts.separator "Program output"
                opts.on("--[no-]verbose", "display output of commands on stdout") do |verbose| end
                opts.on("--[no-]debug", "verbose information (for debugging purposes)") do |debug| end

                opts.on_tail("-h", "--help", "Show this message") do
                    puts opts
                    exit
                end
            end

            parser.parse!(args)
            if !args[0]
                puts parser
                exit
            end

            Rake.application.options.trace = true

            args[0..-1]
        end
    end
end

