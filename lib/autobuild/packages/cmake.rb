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

        attr_reader :defines

        def configurestamp; File.join(builddir, "CMakeCache.txt") end

        def initialize(options)
	    @defines = Hash.new
            super
        end

        def define(name, value)
            @defines[name] = value
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
            end
        end

        # Do the build in builddir
        def build
            Dir.chdir(builddir) do
                Subprocess.run(name, 'build', Autobuild.tool(:make))
            end
            touch_stamp(buildstamp)
        end

        # Install the result in prefix
        def install
            Dir.chdir(builddir) do
                Subprocess.run(name, 'install', Autobuild.tool(:make), 'install')
            end
            touch_stamp(installstamp)
        end
    end
end

