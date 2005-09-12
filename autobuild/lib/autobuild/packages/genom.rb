require 'autobuild/packages/autotools'
require 'open3'

class GenomModule < Autotools
    def initialize(target, options)
        super(target, options)
        get_requires
        get_provides
    end

    def genomstamp; "#{srcdir}/.genom/genom-stamp" end

    def cpp_options
        @options[:genomflags].to_a.find_all { |opt| opt =~ /^-D/ }
    end

    def get_requires
        cpp = ($PROGRAMS['cpp'] || 'cpp')
        Open3.popen3("#{cpp} #{cpp_options.join(" ")} #{srcdir}/#{target}.gen") do |cin, out, err|
            out.each_line { |line|
                if line =~ /^\s*requires\s*:\s*([\w\-]+(?:\s*,\s*[\w\-]+)*);/
                    $1.split(/, /).each { |name| 
                        depends_on name
                        file genomstamp => Package.name2target(name)
                    }
                elsif line =~ /^\s*requires/
                    puts "failed to match #{line}"
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
        cmdline = [ 'genom', target ] | @options[:genomflags].to_a

        file buildstamp => genomstamp
        file genomstamp => [ :genom, "#{srcdir}/#{target}.gen" ] do
            Dir.chdir(srcdir) {
                begin
                    subcommand(target, 'genom', *cmdline)
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
                    subcommand(target, 'genom', *cmdline)
                rescue SubcommandFailed => e
                    raise BuildException.new(e), "failed to generate module #{target}"
                end
            end
        end
    end

    factory :genom, self
end

