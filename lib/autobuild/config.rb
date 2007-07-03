require 'optparse'
require 'rake'
require 'singleton'

# Evaluates +script+ in autobuild context
def Autobuild(&script)
    Autobuild.send(:module_eval, &script)
end

# Main Autobuild module. This module includes the build configuration options
# (see Autobuild::DEFAULT_OPTIONS) for the default values)
# nice:: the nice value at which we should spawn subprocesses
# srcdir:: the base source directory. If a package defines a relative srcdir, then
#          it is defined relatively to Autobuild.srcdir
# prefix:: the base install directory. If a package defines a relative prefix, then
#          it is defined relatively to Autobuild.prefix.
# verbose:: if true, displays all subprocesses output
# debug:: more verbose than 'verbose': displays Rake's debugging output
# do_update:: if we should update the packages
# do_build:: if we should build the packages
# daemonize:: if the build should go into daemon mode (only if the daemons gem is available)
# clean_log:: remove all logs before starting the build
# packages:: a list of packages to build specifically
# default_packages:: the list of packages to build if Autobuild.packages is empty.
#                    It this array is empty too, build all defined packages.
module Autobuild
    class << self
        %w{ nice srcdir prefix
            verbose debug do_update do_build
            daemonize clean_log packages default_packages }.each do |name|
            attr_accessor name
        end

	# Configure the programs used by different packages
        attr_reader :programs
	# The directory in which logs are saved. Defaults to PREFIX/log.
        attr_writer :logdir
    end
    DEFAULT_OPTIONS = { :nice => 0,
        :srcdir => nil, :prefix => nil, :logdir => nil,
        :verbose => false, :debug => false, :do_build => true, :do_update => true, 
        :daemonize => false, :packages => [], :default_packages => [] }

    @programs = Hash.new
    DEFAULT_OPTIONS.each do |name, value|
        send("#{name}=", value)
    end

    def self.post_install(*args, &block)
	if args.empty?
	    @post_install_handler = block
	elsif !block
	    @post_install_handler = args
	else
	    raise ArgumentError, "cannot set both arguments and block"
	end
    end
    attr_reader :post_install_handler

    def self.apply_post_install(info)
	return unless info

	case info
	when Array
	    args = info.dup
	    tool = Autobuild.tool(args.shift)

	    Autobuild::Subprocess.run name, 'post-install', tool, *args
	when Proc
	    info.call
	end
    end

    @mail = Hash.new
    class << self
	# Mailing configuration. It is a hash with the following keys (as symbols)
	# [:to] the mail destination. Defaults to USER@HOSTNAME, where USER is the username
	#       of autobuild's caller, and HOSTNAME the hostname of the current machine.
	# [:from] the mail origin. Defaults to the same value than +:to+
	# [:smtp] the hostname of the SMTP server, defaults to localhost
	# [:port] the port of the SMTP server, defauts to 22
	# [:only_errors] mail only on errors. Defaults to false.
	attr_reader :mail

	# The directory in which logs are saved
        def logdir; @logdir || "#{prefix}/log" end

	# Removes all log files
        def clean_log!
            Reporting.each_log do |file|
                FileUtils.rm_f file
            end
        end

        # Get a given program, using its name as default value. For
	# instance
	#   tool('automake') 
	# will return 'automake' unless the autobuild script defined
	# another automake program in Autobuild.programs by doing
	#   Autobuild.programs['automake'] = 'automake1.9'
        def tool(name)
            programs[name.to_sym] || programs[name.to_s] || name.to_s
        end

	# Gets autobuild options from the command line and returns the
	# remaining elements
        def commandline(args)
            parser = OptionParser.new do |opts|
                opts.separator "Path specification"
                opts.on("--srcdir PATH", "sources are installed in PATH") do |@srcdir| end
                opts.on("--prefix PATH", "built packages are installed in PATH") do |@prefix| end
                opts.on("--logdir PATH", "logs are saved in PATH (default: <prefix>/autobuild)") do |@logdir| end

                opts.separator ""
                opts.separator "General behaviour"
                opts.on('--nice NICE', Integer, 'nice the subprocesses to the given value') do |@nice| end
                opts.on("-h", "--help", "Show this message") do
                    puts opts
                    exit
                end
		if defined? Daemons
		    opts.on("--[no-]daemon", "go into daemon mode") do |@daemonize| end
		end
                opts.on("--[no-]update", "update already checked-out sources") do |@do_update| end
                opts.on("--[no-]build",  "only prepare packages, do not build them") do |@do_build| end 

                opts.separator ""
                opts.separator "Program output"
                opts.on("--[no-]verbose", "display output of commands on stdout") do |@verbose| end
                opts.on("--[no-]debug", "debug information (for debugging purposes)") do |@debug| end

                opts.separator ""
		opts.separator "Mail reports"
		opts.on("--mail-from EMAIL", String, "From: field of the sent mails") do |from_email|
		    mail[:from] = from_email
		end
		opts.on("--mail-to EMAILS", String, "comma-separated list of emails to which the reports should be sent") do |emails| 
		    mail[:to] ||= []
		    mail[:to] += emails.split(',')
		end
		opts.on("--mail-subject SUBJECT", String, "Subject: field of the sent mails") do |subject_email|
		    mail[:subject] = subject_email
		end
		opts.on("--mail-smtp HOSTNAME", String, " address of the mail server written as hostname[:port]") do |smtp|
		    raise "invalid SMTP specification #{smtp}" unless smtp =~ /^([^:]+)(?::(\d+))?$/
		    mail[:smtp] = $1
		    mail[:port] = Integer($2) unless $2.empty?
		end
		opts.on("--mail-only-errors", "send mail only on errors") do
		    mail[:only_errors] = true
		end

            end

            parser.parse!(args)
            if !args[0]
                puts parser
                exit
            end

            Rake.application.options.trace = debug

            args[0..-1]
        end
    end
end

