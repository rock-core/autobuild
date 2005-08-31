require 'autobuild/packages/autotools'

class GenomModule < Autotools
    def initialize(target, options)
        super(target, options)
        get_requires
        get_provides
    end

    def genomstamp; "#{srcdir}/.genom/genom-stamp" end

    def get_requires
        File.open("#{srcdir}/#{target}.gen") do |f|
            f.each_line { |line|
                if line =~ /^require\s*:\s*([\w\-]+(?:\s*,\s*[\w\-]+)*);/
                    $1.split(/, /).each { |name| 
                        depends_on name
                        file genomstamp => Package.name2target(name)
                    }
                elsif line =~ /^require/
                    puts "failed to math #{line}"
                end
            }
        end
    end

    def get_provides
        File.open("#{srcdir}/configure.ac.user") do |f|
            f.each_line { |line|
                if line =~ /^\s*EXTRA_PKGCONFIG\s*=\s*"?([\w\-]+(?:\s+[\w\-]+)*)"?/
                    $1.split(/\s+/).each { |pkg|
                        provides pkg
                    }
                end
            }
        end
    end
        

    def regen_targets
        file buildstamp => genomstamp
        file genomstamp => [ :genom, "#{srcdir}/#{target}.gen" ] do
            Dir.chdir(srcdir) {
                cmdline = "genom " + @options[:genomflags].to_a.join(" ") + " #{target}"
                begin
                    subcommand(target, 'genom', cmdline)
                rescue SubcommandFailed => e
                    raise BuildException.new(e), "failed to generate module #{target}"
                end
            }
        end

        acuser = "#{srcdir}/configure.ac.user"
        if File.exists?(acuser)
            file "#{srcdir}/configure" => acuser do
                # configure does not depend on the .gen file
                # since the generation takes care of rebuilding configure
                # if .gen has changed
                begin
                    subcommand(target, 'genom', cmdline)
                rescue SubcommandFailed => e
                    raise BuildException.new(e), "failed to generate module #{target}"
                end
            end
        end
    end

    factory :genom, self
end

