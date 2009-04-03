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
        end

        # a key => value association of defines for CMake
        attr_reader :defines
        # If true, always run cmake before make during the build
        attr_accessor :always_reconfigure

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
                    Subprocess.run(name, 'doc', Autobuild.tool(:make), target)
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

        def prepare
            super

            all_defines = defines.dup
            all_defines['CMAKE_INSTALL_PREFIX'] = prefix

            if !File.exists?( File.join(builddir, 'Makefile') )
                FileUtils.rm configurestamp
            end

            if File.exists?(configurestamp)
                cache = File.read(configurestamp)
                did_change = all_defines.any? do |name, value|
                    cache_line = cache.find do |line|
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
                    FileUtils.rm configurestamp
                end
            end
        end

        # Configure the builddir directory before starting make
        def configure
            if File.exists?(builddir) && !File.directory?(builddir)
                raise ConfigException, "#{builddir} already exists but is not a directory"
            end

            FileUtils.mkdir_p builddir if !File.directory?(builddir)
            Dir.chdir(builddir) do
                command = [ "cmake", "-DCMAKE_INSTALL_PREFIX=#{prefix}" ]
                defines.each do |name, value|
                    command << "-D#{name}=#{value}"
                end
                command << srcdir
                
                Subprocess.run(name, 'configure', *command)
                super
            end
        end

        # Do the build in builddir
        def build
            Dir.chdir(builddir) do
                if always_reconfigure || !File.file?('Makefile')
                    Subprocess.run(name, 'build', Autobuild.tool(:cmake), '.')
                end
                Subprocess.run(name, 'build', Autobuild.tool(:make))
            end
            touch_stamp(buildstamp)
        end

        # Install the result in prefix
        def install
            Dir.chdir(builddir) do
                Subprocess.run(name, 'install', Autobuild.tool(:make), 'install')
            end
            super
        end
    end
end

