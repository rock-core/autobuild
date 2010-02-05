require 'autobuild/configurable'

module Autobuild
    def self.cmake(options, &block)
        CMake.new(options, &block)
    end

    class CMake < Configurable
        class << self
            def builddir; @builddir || Configurable.builddir end
            def builddir=(new)
                raise ConfigException, "absolute builddirs are not supported" if (Pathname.new(new).absolute?)
                raise ConfigException, "builddir must be non-nil and non-empty" if (new.nil? || new.empty?)
                @builddir = new
            end

            attr_writer :full_reconfigures
            def full_reconfigures?
                @full_reconfigures
            end
        end
        @full_reconfigures = true

        # a key => value association of defines for CMake
        attr_reader :defines
        # If true, always run cmake before make during the build
        attr_accessor :always_reconfigure
        # If true, we always remove the CMake cache before reconfiguring.
        # 
        # See #full_reconfigures? for more details
        attr_writer :full_reconfigures

        # If true, we always remove the CMake cache before reconfiguring. This
        # is to workaround the aggressive caching behaviour of CMake, and is set
        # to true by default.
        #
        # See CMake.full_reconfigures? and CMake.full_reconfigures= for a global
        # setting
        def full_reconfigures?
            if @full_reconfigures.nil?
                CMake.full_reconfigures?
            else
                @full_reconfigures
            end
        end

        def configurestamp; File.join(builddir, "CMakeCache.txt") end

        def initialize(options)
	    @defines = Hash.new
            super
        end

        def define(name, value)
            @defines[name] = value
        end

        def install_doc
            super(builddir)
        end

        # Declare that the given target can be used to generate documentation
        def with_doc(target = 'doc')
            doc_task do
                Dir.chdir(builddir) do
                    progress "generating documentation for %s"
                    Subprocess.run(self, 'doc', Autobuild.tool(:make), "-j#{parallel_build_level}", target)
                    yield if block_given?
                end
            end
        end

        CMAKE_EQVS = {
            'ON' => 'ON',
            'YES' => 'ON',
            'OFF' => 'OFF',
            'NO' => 'OFF'
        }
        def equivalent_option_value?(old, new)
            if old == new
                true
            else
                old = CMAKE_EQVS[old]
                new = CMAKE_EQVS[new]
                if old && new
                    old == new
                else
                    false
                end
            end
        end

        def import
            super

            Dir.glob(File.join(srcdir, "*.pc.in")) do |file|
                file = File.basename(file, ".pc.in")
                provides "pkgconfig/#{file}"
            end
        end

        def prepare

            all_defines = defines.dup
            all_defines['CMAKE_INSTALL_PREFIX'] = prefix

            if !File.exists?( File.join(builddir, 'Makefile') )
                FileUtils.rm_f configurestamp
            end

            if File.exists?(configurestamp)
                cache = File.read(configurestamp)
                did_change = all_defines.any? do |name, value|
                    cache_line = cache.each_line.find do |line|
                        line =~ /^#{name}:/
                    end

                    value = value.to_s
                    old_value = cache_line.split("=")[1].chomp if cache_line
                    if !old_value || !equivalent_option_value?(old_value, value)
                        if Autobuild.debug
                            puts "option '#{name}' changed value: '#{old_value}' => '#{value}'"
                        end
                        
                        true
                    end
                end
                if did_change
                    if Autobuild.debug
                        puts "CMake configuration changed, forcing a reconfigure"
                    end
                    FileUtils.rm_f configurestamp
                end
            end

            super
        end

        # Configure the builddir directory before starting make
        def configure
            super do
                Dir.chdir(builddir) do
                    command = [ "cmake", "-DCMAKE_INSTALL_PREFIX=#{prefix}" ]
                    defines.each do |name, value|
                        command << "-D#{name}=#{value}"
                    end
                    command << srcdir
                    
                    progress "generating and configuring build system for %s"
                    if full_reconfigures?
                        FileUtils.rm_f configurestamp
                    end
                    Subprocess.run(self, 'configure', *command)
                end
            end
        end

        # Do the build in builddir
        def build
            Dir.chdir(builddir) do
                progress_with_value "building %s"
                if always_reconfigure || !File.file?('Makefile')
                    Subprocess.run(self, 'build', Autobuild.tool(:cmake), '.')
                end
                Subprocess.run(self, 'build', Autobuild.tool(:make), "-j#{parallel_build_level}") do |line|
                    if line =~ /\[\s+(\d+)%\]/
                        progress_value Integer($1)
                    end
                end
            end
            Autobuild.touch_stamp(buildstamp)
        end

        # Install the result in prefix
        def install
            Dir.chdir(builddir) do
                progress "installing %s"
                Subprocess.run(self, 'build', Autobuild.tool(:make), "-j#{parallel_build_level}", 'install')
            end
            super
        end
    end
end

