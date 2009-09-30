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

module Autobuild
    def self.progress(msg)
	puts "  #{msg}"
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
        def self.each_log
            Find.find(Autobuild.logdir) do |path|
                if File.file?(path) && path =~ /\.log$/
                    yield(path)
                end
            end
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
	    smtp = Net::SMTP.new(smtp_hostname, smtp_port)
	    smtp.start {
		to_email.each do |email|
		    mail.header.to = email
		    smtp.send_mail RMail::Serialize.write('', mail), from_email, email
		end
	    }

            # Notify the sending
            puts "Sent notification mail to #{to_email} with source #{from_email}"
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


