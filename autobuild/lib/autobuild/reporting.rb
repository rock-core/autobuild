require 'rmail'
require 'rmail/serialize'
require 'net/smtp'
require 'socket'

module Reporting
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
        message = "Build finished successfully at #{Time.now}"
        puts message
        send_mail("Build success", message) if $MAIL
    end

    def self.error(object)
        if object.kind_of?(SubcommandFailed)
            body = <<EOF
#{object.target}: #{object.message}
    command '#{object.command}' failed with status #{object.status}
    see #{File.basename(object.logfile)} for details
EOF

            message = <<EOF
#{object.target}: #{object.message}
    command '#{object.command}' failed with status #{object.status}
    see #{object.logfile} for details
EOF
        else
            body = message = "#{object.target}: #{object.message}"
        end

        puts message
        send_mail("Build failed", body) if $MAIL && object.mail?
    end

    private

    def self.send_mail(subject, body)
        from = ($MAIL[:from] || "autobuild@#{Socket.gethostname}")
        to = $MAIL[:to]
        smtp = ($MAIL[:smtp]  || "localhost" )

        mail = RMail::Message.new
        mail.header.date = Time.now
        mail.header.from = from
        mail.header.to = to
        mail.header.subject = subject

        part = RMail::Message.new
        part.header.set('Content-Type', 'text/plain')
        part.body = body
        mail.add_part(part)

        # Attach log files
        Dir.glob("#{$LOGDIR}/*.log") do |file|
            mail.add_file(file)
        end

        # Send the mail
        smtp = Net::SMTP.new(smtp, Integer($MAIL[:port] || 25))
        smtp.start {
            smtp.send_mail RMail::Serialize.write('', mail), from, to
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


