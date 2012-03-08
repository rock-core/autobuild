require 'autobuild/packages/autotools'
require 'open3'
require 'autobuild/pkgconfig'

module Autobuild
    def self.genom(opts, &proc)
        GenomModule.new(opts, &proc)
    end

    class GenomModule < Autotools
        attr_accessor :genomflags

        def initialize(*args, &config)
            @genomflags = []
            super

	    use :autogen => 'autogen'
        end

	def import
	    super
	    get_provides
	end

        # Called before running the rake tasks and
        # after all imports have been made
        def prepare
	    genomflags.flatten!
	    get_requires

            super

	    file genomstamp => dependencies.map { |p| Package[p].installstamp }
        end

        # The file touched by genom on successful generation
	def genomstamp; File.join(srcdir, '.genom', 'genom-stamp') end

        # Extract the cpp options from the genom options
        def cpp_options
            [*genomflags].find_all { |opt| opt =~ /^-D/ }
        end

        # Extracts dependencies using the requires: field in the .gen file
        def get_requires
	    apionly = genomflags.find { |f| f == '-a' }
            cpp = Autobuild.tool(:cpp)
            currentBuffer = nil
            Open3.popen3("#{cpp} #{cpp_options.join(" ")} #{srcdir}/#{name}.gen") do |cin, out, err|
                out.each_line do |line|
                    if line =~ /^\s*(codels_)?requires\s*:.*$/
                        currentBuffer = ""
                    end
                    if currentBuffer
                        currentBuffer += line
                        if currentBuffer =~ /^\s*(codels_)?requires\s*:\s*(\"?\s*[\w\-=><0-9.\s]+\s*\"?(?:\s*,\s*\"?\s*[\w\-=><0-9.\s]+\s*\"?)*);/
                            # Remove the codels_requires lines if -a is given to genom
                            unless $1 == "codels_" && apionly
                                $2.split(/,/).each do |name|
                                    if name.strip =~ /\s*\"?\s*([\w\-]+)\s*[<=>]+\s*[0-9.]+\s*\"?\s*/
                                        depends_on $1
                                    else
                                        depends_on name.strip
                                    end
                                end
                            end
                            currentBuffer = nil
                        elsif currentBuffer =~ /^\s*(?:codels_)?requires.*;$/
                            # Check that the regexp is not too strict
                            STDERR.puts "failed to match #{currentBuffer}"
                        end
                    end
                end
            end
        end

        # Alias this package to the ones defined in the EXTRA_PKGCONFIG 
        # flag in configure.ac.user
        def get_provides
	    configure_ac_user = File.join(srcdir, 'configure.ac.user')
	    return unless File.readable?(configure_ac_user)
            File.open(configure_ac_user) do |f|
                f.each_line { |line|
                    if line =~ /^\s*EXTRA_PKGCONFIG\s*=\s*"?([\w\-]+(?:\s+[\w\-]+)*)"?/
                        $1.split(/\s+/).each { |pkg| provides pkg }
                    end
                }
            end
        end

	# Make the genom-stamp file depend on
	#   * genom includes
	#   * genom canvas
	#   * the genom binary itself
	def genom_dependencies
	    # Get the genom pkg-config
	    if Package['genom']
		'genom'
	    else
		genom_pkg = PkgConfig.new('genom')

		includedir = File.join(genom_pkg.includedir, 'genom')
		Autobuild.source_tree includedir

		canvasdir = File.join(genom_pkg.prefix, "share", "genom", genom_pkg.version);;
		Autobuild.source_tree canvasdir

		binary = File.join(genom_pkg.exec_prefix, "bin", "genom")
		file binary

		[binary, includedir, canvasdir]
	    end
	end

        def regen
            cmdline = [ 'genom', "#{name}.gen", *genomflags ]

	    # Check that the module has been generated with the same flags
	    genom_mk = "#{srcdir}/autoconf/genom.mk"
	    if File.exists?(genom_mk)
		contents = File.open(genom_mk).readlines
		old_file = contents.find { |l| l =~ /^GENFILE/ }.gsub('GENFILE=', '').strip
		old_flags = Shellwords.shellwords(
			    contents.find { |l| l =~ /^GENFLAGS/ }.gsub('GENFLAGS=', ''))

		if old_file != "#{name}.gen" || !(old_flags - genomflags).empty? || !(genomflags - old_flags).empty?
		    FileUtils.rm_f genomstamp
		end
	    end

            file buildstamp => genomstamp
	    file genomstamp => genom_dependencies
            file genomstamp => srcdir do
                isolate_errors do
                    in_dir(srcdir) do
                        progress_start "generating GenoM files for %s" do
                            Subprocess.run(self, 'genom', *cmdline)
                        end
                    end
                end
            end

            acuser = File.join(srcdir, "configure.ac.user")
            file File.join(srcdir, 'configure') => acuser do
                isolate_errors do
                    # configure does not depend on the .gen file
                    # since the generation takes care of rebuilding configure
                    # if .gen has changed
                    progress_start "generating build system for %s" do
                        in_dir(srcdir) { Subprocess.run(self, 'genom', File.expand_path('autogen')) }
                    end
                end
            end

	    super("#{srcdir}/autoconf/configure.ac")
        end
    end
end

