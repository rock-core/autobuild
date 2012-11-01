begin
    require 'rmail'
    require 'rmail/serialize'
    Autobuild::HAS_RMAIL = true
rescue LoadError
    Autobuild::HAS_RMAIL = false
end

require 'net/smtp'
require 'socket'
require 'etc'
require 'find'

require 'autobuild/config'
require 'autobuild/exceptions'
require 'thread'

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


    def self.message(*args)
        return if silent?
        display_lock.synchronize do
            display_message(*args)
        end
    end

    def self.display_message(*args)
        msg =
            if args.empty? then ""
            else "#{color(*args)}"
            end

        size =
            if @last_progress_msg then @last_progress_msg.size
            else 0
            end

        puts "\r#{msg}#{" " * [size - msg.size, 0].max}"
        if @last_progress_msg
            print "#{@last_progress_msg}"
        end
    end

    class << self
        attr_reader :progress_messages
    end
    @progress_messages = Array.new

    # Displays an error message
    def self.error(message)
        Autobuild.message("  ERROR: #{message}", :red, :bold)
    end

    # Displays a warning message
    def self.warn(message)
        Autobuild.message("  WARN: #{message}", :magenta)
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
            display_progress
        end

        if block_given?
            begin
                yield
                if options[:done_message]
                    progress(key, *options[:done_message])
                end
                progress_done(key, true)
            rescue Exception => e
                progress_done(key, false)
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
            if found && @last_progress_msg
                display_message("  #{last_msg}") if display_last && last_msg
                display_progress
            end
        end
        found
    end

    def self.display_progress
        msg = "#{progress_messages.map(&:last).sort.join(" | ")}"
        if @last_progress_msg 
            if !silent?
                print "\r" + " " * @last_progress_msg.length
            end
        end

        if msg.empty?
            print "\r" if !silent?
            @last_progress_msg = nil
        else
            msg = "  #{msg}"
            print "\r#{msg}" if !silent?
            @last_progress_msg = msg
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
                    if pkg.failed?
                        errors.concat(pkg.failures)
                    end
                end

                if !errors.empty?
                    raise CompositeException.new(errors)
                end

            rescue Autobuild::Exception => e
                error(e)
                exit(1) if e.fatal?
            end
        end
        
        ## Reports a successful build to the user
        def self.success
            @@reporters.each do |rep| rep.success end
        end

        ## Reports that the build failed to the user
        def self.error(error)
            @@reporters.each do |rep| rep.error(error) end
        end

        ## Add a new reporter
        def self.<<(reporter)
            @@reporters << reporter
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
            puts "Build failed: #{error}"
        end
        def success
            puts "Build finished successfully at #{Time.now}"
            if Autobuild.post_success_message
                puts Autobuild.post_success_message
            end
        end
    end
end

## Report by mail
if Autobuild::HAS_RMAIL
module Autobuild
    class MailReporter < Reporter
        def default_mail
            Etc::endpwent
            uname = while (pwent = Etc::getpwent)
                        break (pwent.name) if pwent.uid == Process.uid
                    end

            raise "FATAL: cannot find a user with uid=#{Process.uid}" unless uname
            "#{pwent.name}@#{Socket.gethostname}"
        end
        
	attr_reader :from_email, :to_email, :smtp_hostname, :smtp_port, :subject, :only_errors
        def initialize(config)
            @from_email = (config[:from] || default_mail)
            @to_email   = (config[:to]   || default_mail)
	    @subject = (config[:subject] || "Build %result% on #{Socket.gethostname} at %time%")
	    @only_errors = config[:only_errors]
            @smtp_hostname = (config[:smtp] || "localhost" )
            @smtp_port = Integer(config[:port] || Socket.getservbyname('smtp'))
        end

        def error(error)
            if error.mail?
                send_mail("failed", error.to_s)
            end
        end

        def success
	    unless only_errors
		send_mail("success", Autobuild.post_success_message || "")
	    end
        end

        def send_mail(result, body = "")
            mail = RMail::Message.new
            mail.header.date = Time.now
            mail.header.from = from_email
            mail.header.subject = subject.
		gsub('%result%', result).
		gsub('%time%', Time.now.to_s).
		gsub('%hostname%', Socket.gethostname)

            part = RMail::Message.new
            part.header.set('Content-Type', 'text/plain')
            part.body = body
            mail.add_part(part)

            # Attach log files
            Reporting.each_log do |file|
                name = file[Autobuild.logdir.size..-1]
                mail.add_file(name, file)
            end

            # Send the mails
            if smtp_hostname =~ /\// && File.directory?(File.dirname(smtp_hostname))
                File.open(smtp_hostname, 'w') do |io|
                    io.puts "From: #{from_email}"
                    io.puts "To: #{to_email.join(" ")}"
                    io.write RMail::Serialize.write('', mail)
                end
                puts "saved notification email in #{smtp_hostname}"
            else
                smtp = Net::SMTP.new(smtp_hostname, smtp_port)
                smtp.start {
                    to_email.each do |email|
                        mail.header.to = email
                        smtp.send_mail RMail::Serialize.write('', mail), from_email, email
                    end
                }

                # Notify the sending
                puts "sent notification mail to #{to_email} with source #{from_email}"
            end
        end
    end
end

module RMail
    class Message
        ## Attachs a file to a message
        def add_file(name, path, content_type='text/plain')
            part = RMail::Message.new
            part.header.set('Content-Type', content_type)
            part.header.set('Content-Disposition', 'attachment', 'filename' => name)
            part.body = ''
            File.open(path) do |file|
                part.body << file.readlines.join("")
            end
            self.add_part(part)
        end
    end
end
end # if Autobuild::HAS_RMAIL


