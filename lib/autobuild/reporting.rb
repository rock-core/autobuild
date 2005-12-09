require 'rmail'
require 'rmail/serialize'
require 'net/smtp'
require 'socket'
require 'etc'

require 'autobuild/exceptions'

module Autobuild
    ## The reporting module provides the framework
    # to run commands in autobuild and report errors 
    # to the user
    #
    # It does not use a logging framework like Log4r, but it should ;-)
    module Reporting
        @@reporters = Array.new

        ## Run a block and report known exception
        # If an exception is fatal, the program is terminated using exit()
        #
        # :yield:
        def self.report
            begin
                yield
            rescue Autobuild::Exception => e
                raise unless e.kind_of?(Autobuild::Exception)
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

        ## Iterate on all log files
        def self.each_log(&iter)
            Dir.glob("#{$LOGDIR}/*.log", &iter)
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
        end
    end

    ## Report by mail
    class MailReporter < Reporter
        def default_mail
            Etc::endpwent
            uname = while (pwent = Etc::getpwent)
                        break (pwent.name) if pwent.uid == Process.uid
                    end

            raise "FATAL: cannot find a user with uid=#{Process.uid}" unless uname
            "#{pwent.name}@#{Socket.gethostname}"
        end
        
        def initialize(config)
            @from = (config[:from] || default_mail)
            @to   = (config[:to]   || default_mail)
            @smtp = (config[:smtp] || "localhost" )
            @port = Integer(config[:port] || Socket.getservbyname('smtp'))
        end

        def error(error)
            if error.mail?
                send_mail("Build failed", error.to_s)
            end
        end

        def success
            send_mail("Build success", "finished successfully at #{Time.now}")
        end

        def send_mail(subject, body)
            mail = RMail::Message.new
            mail.header.date = Time.now
            mail.header.from = @from
            mail.header.to = @to
            mail.header.subject = subject

            part = RMail::Message.new
            part.header.set('Content-Type', 'text/plain')
            part.body = body
            mail.add_part(part)

            # Attach log files
            Reporting.each_log do |file|
                mail.add_file(file)
            end

            # Send the mail
            smtp = Net::SMTP.new(@smtp, @port)
            smtp.start {
                smtp.send_mail RMail::Serialize.write('', mail), @from, @to
            }

            # Notify the sending
            puts "Sent notification mail to #{@to} with source #{@from}"

        end
    end
end

module RMail
    class Message
        ## Attachs a file to a message
        def add_file(path, content_type='text/plain')
            part = RMail::Message.new
            part.header.set('Content-Type', content_type)
            part.header.set('Content-Disposition', 'attachment', 'filename' => File.basename(path))
            part.body = ''
            File.open(path) do |file|
                part.body << file.readlines.join("\n")
            end
            self.add_part(part)
        end
    end
end


