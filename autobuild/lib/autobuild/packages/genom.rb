require 'autobuild/packages/autotools'
require 'open3'

module Autobuild
    def self.genom(opts, &proc)
        GenomModule.new(opts, &proc)
    end

    class GenomModule < Autotools
        # Called before running the rake tasks and
        # after all imports have been made
        def prepare
            super
            get_requires
            get_provides
        end

        # The file touched by genom on successful generation
        def genomstamp; "#{srcdir}/.genom/genom-stamp" end

        # Extract the cpp options from the genom options
        def cpp_options
            @options[:genomflags].to_a.find_all { |opt| opt =~ /^-D/ }
        end

        # Extracts dependencies using the requires: field in the .gen file
        def get_requires
            cpp = Autobuild.tool(:cpp)
            Open3.popen3("#{cpp} #{cpp_options.join(" ")} #{srcdir}/#{name}.gen") do |cin, out, err|
                out.each_line { |line|
                    if line =~ /^\s*requires\s*:\s*([\w\-]+(?:\s*,\s*[\w\-]+)*);/
                        $1.split(/, /).each { |name| depends_on name }
                    elsif line =~ /^\s*requires/
                        puts "failed to match #{line}"
                    end
                }
            end
        end

        # Alias this package to the ones defined in the EXTRA_PKGCONFIG 
        # flag in configure.ac.user
        def get_provides
            File.open("#{srcdir}/configure.ac.user") do |f|
                f.each_line { |line|
                    if line =~ /^\s*EXTRA_PKGCONFIG\s*=\s*"?([\w\-]+(?:\s+[\w\-]+)*)"?/
                        $1.split(/\s+/).each { |pkg| provides pkg }
                    end
                }
            end
        end
            
        def depends_on(*packages)
            super
            file genomstamp => packages
        end

        def regen_targets
            cmdline = [ 'genom', name ] | @options[:genomflags].to_a

            file buildstamp => genomstamp
            file genomstamp => [ "#{srcdir}/#{name}.gen" ] do
                Dir.chdir(srcdir) {
                    Subprocess.run(name, 'genom', *cmdline)
                }
            end

            acuser = "#{srcdir}/configure.ac.user"
            file "#{srcdir}/configure" => acuser do
                # configure does not depend on the .gen file
                # since the generation takes care of rebuilding configure
                # if .gen has changed
                Dir.chdir(srcdir) { Subprocess.run(name, 'genom', File.expand_path('autogen')) }
            end
        end
    end
end

