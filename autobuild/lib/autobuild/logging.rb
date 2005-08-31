require 'rmail'
require 'rmail/serialize'
require 'net/smtp'
require 'socket'

class SubcommandFailed < Exception
    attr_reader :target, :command, :logfile, :status
    def initialize(target, command, logfile, status)
        @target = target
        @command = command
        @logfile = logfile
        @status = status
    end
end
        
class ConfigException < Exception
    def mail?; false end
end

class ImportException < SubcommandFailed
    def mail?; true end

    def initialize(subcommand)
        super(subcommand.target, subcommand.command, subcommand.logfile, subcommand.status)
    end
end
class BuildException < SubcommandFailed
    def mail?; true end

    def initialize(subcommand)
        super(subcommand.target, subcommand.command, subcommand.logfile, subcommand.status)
    end
end

def success
    message = "Build finished successfully at #{Time.now}"
    puts message
    send_mail("Build success", message) if $MAIL
end

def error(object, place)
    if object.kind_of?(SubcommandFailed)
        body = <<EOF
#{place}: #{object.message}
    command '#{object.command}' failed with status #{object.status}
    see #{File.basename(object.logfile)} for details
EOF

        message = <<EOF
#{place}: #{object.message}
    command '#{object.command}' failed with status #{object.status}
    see #{object.logfile} for details
EOF
    else
        body = message = "#{place}: #{object.message}"
    end

    puts message
    send_mail("Build failed", body) if $MAIL
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

def send_mail(subject, body)
    from = ($MAIL['from'] || "autobuild@#{Socket.gethostname}")
    to = $MAIL['to']
    smtp = ($MAIL['smtp']  || "localhost" )

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
    smtp = Net::SMTP.new(smtp, Integer($MAIL['port'] || 25))
    smtp.start {
        smtp.send_mail RMail::Serialize.write('', mail), from, to
    }
end


