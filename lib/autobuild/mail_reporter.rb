begin
    require 'rmail'
    require 'rmail/serialize'
    Autobuild::HAS_RMAIL = true
rescue LoadError
    Autobuild::HAS_RMAIL = false
end

## Report by mail
if Autobuild::HAS_RMAIL
    module Autobuild
        class MailReporter < Reporter
            def default_mail
                Etc.endpwent
                uname = while (pwent = Etc.getpwent)
                            break pwent.name if pwent.uid == Process.uid
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
                @smtp_hostname = (config[:smtp] || "localhost")
                @smtp_port = Integer(config[:port] || Socket.getservbyname('smtp'))
            end

            def error(error)
                send_mail("failed", error.to_s) if error.mail?
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
                if smtp_hostname =~ %r{/} && File.directory?(File.dirname(smtp_hostname))
                    File.open(smtp_hostname, 'w') do |io|
                        io.puts "From: #{from_email}"
                        io.puts "To: #{to_email.join(' ')}"
                        io.write RMail::Serialize.write('', mail)
                    end
                    puts "saved notification email in #{smtp_hostname}"
                else
                    smtp = Net::SMTP.new(smtp_hostname, smtp_port)
                    smtp.start do
                        to_email.each do |email|
                            mail.header.to = email
                            smtp.send_mail RMail::Serialize.write('', mail), from_email, email
                        end
                    end

                    # Notify the sending
                    puts "sent notification mail to #{to_email} with source #{from_email}"
                end
            end
        end
    end

    module RMail
        class Message
            ## Attachs a file to a message
            def add_file(name, path, content_type = 'text/plain')
                part = RMail::Message.new
                part.header.set('Content-Type', content_type)
                part.header.set('Content-Disposition', 'attachment', 'filename' => name)
                part.body = ''
                File.open(path) do |file|
                    part.body << file.readlines.join("")
                end
                add_part(part)
            end
        end
    end
end
