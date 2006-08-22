require 'autobuild/packages/autotools'
require 'open3'
require 'autobuild/pkgconfig'

module Autobuild
    def self.genom(opts, &proc)
        GenomModule.new(opts, &proc)
    end

    class GenomModule < Autotools
	# Get the genom pkg-config
	@@genom = PkgConfig.new('genom')

        attr_accessor :genomflags

        def initialize(*args, &config)
            @genomflags = []
            super

	    use :autogen => 'autogen'
        end

        # Called before running the rake tasks and
        # after all imports have been made
        def prepare

            super
            get_requires
            get_provides
        end

        # The file touched by genom on successful generation
	def genomstamp; File.join(srcdir, '.genom', 'genom-stamp') end

        # Extract the cpp options from the genom options
        def cpp_options
            [*genomflags].find_all { |opt| opt =~ /^-D/ }
        end

        # Extracts dependencies using the requires: field in the .gen file
        def get_requires
            cpp = Autobuild.tool(:cpp)
            Open3.popen3("#{cpp} #{cpp_options.join(" ")} #{srcdir}/#{name}.gen") do |cin, out, err|
                out.each_line { |line|
                    if line =~ /^\s*(?:codel_)?requires\s*:\s*([\w\-]+(?:\s*,\s*[\w\-]+)*);/
                        $1.split(/, /).each { |name| depends_on name }
                    elsif line =~ /^\s*(?:codel_)?requires/
                        puts "failed to match #{line}"
                    end
                }
            end
        end

        # Alias this package to the ones defined in the EXTRA_PKGCONFIG 
        # flag in configure.ac.user
        def get_provides
            File.open(File.join(srcdir, 'configure.ac.user')) do |f|
                f.each_line { |line|
                    if line =~ /^\s*EXTRA_PKGCONFIG\s*=\s*"?([\w\-]+(?:\s+[\w\-]+)*)"?/
                        $1.split(/\s+/).each { |pkg| provides pkg }
                    end
                }
            end
        end
            
        def depends_on(*packages)
            super
	    file genomstamp => packages.map { |p| Package[p].installstamp }
	end

	# Make the genom-stamp file depend on
	#   * genom includes
	#   * genom canvas
	#   * the genom binary itself
	def genom_dependencies
	    includedir = @@genom.includedir
	    source_tree includedir

	    canvasdir = File.join(@@genom.prefix, "share", "genom", @@genom.version);;
	    source_tree canvasdir

	    binary = File.join(@@genom.exec_prefix, "bin", "genom")
	    file binary

	    [binary, includedir, canvasdir]
	end

        def regen
            cmdline = [ 'genom', "#{name}.gen", *genomflags ]

            file buildstamp => genomstamp
	    file genomstamp => genom_dependencies
            file genomstamp => srcdir do
                Dir.chdir(srcdir) do
                    Subprocess.run(name, 'genom', *cmdline)
		end
            end

            acuser = File.join(srcdir, "configure.ac.user")
            file File.join(srcdir, 'configure') => acuser do
                # configure does not depend on the .gen file
                # since the generation takes care of rebuilding configure
                # if .gen has changed
                Dir.chdir(srcdir) { Subprocess.run(name, 'genom', File.expand_path('autogen')) }
            end
        end
    end
end

