require 'rmail'
require 'rmail/serialize'
require 'net/smtp'
require 'socket'

class Reporting
    @@reporters = Array.new

    def self.report
        begin
            yield
        rescue Exception => e
            raise unless e.respond_to?(:target)
            error(e)
            exit(1) if e.fatal?
        end
    end
    
    def self.success
        @@reporters.each do |rep| rep.success end
    end

    def self.error(error)
        @@reporters.each do |rep| rep.error(error) end
    end

    def self.<<(reporter)
        @@reporters << reporter
    end

    def self.each_log(&iter)
        Dir.glob("#{$LOGDIR}/*.log", &iter)
    end
end

class Reporter
    def error(error); end
    def success; end
end

class StdoutReporter < Reporter
    def error(error)
        puts "Build failed: #{error}"
    end
    def success
        puts "Build finished successfully at #{Time.now}"
    end
end

class MailReporter < Reporter
    def initialize(from, to, smtp = nil, port = 25)
        @from = (from || "autobuild@#{Socket.gethostname}")
        @to   = to
        @smtp = (smtp || "localhost" )
        @port = Integer(port || 25)
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
    end
end

module RMail
    class Message
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


