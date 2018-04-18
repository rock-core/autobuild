require 'autobuild/configurable'

# Main Autobuild module
module Autobuild
    def self.python(opts, &proc)
        Python.new(opts, &proc)
    end

    # Handler class to build python-based packages
    class Python < Configurable
        attr_accessor   :buildflags
        attr_accessor   :installflags

        def configurestamp
            "#{builddir}/configure-autobuild-stamp"
        end

        def initialize(options)
            @buildflags = []
            @installflags = []
            super
        end

        def prepare_for_forced_build
            super
            FileUtils.rm_f configurestamp
            @forced = true
        end

        # There is nothing to configure
        def configure
            super {}
        end

        def generate_build_command
            command = ['python', 'setup.py', 'build']
            command << "--build-base=#{builddir}"
            command += buildflags.flatten
            command
        end

        def generate_install_command
            command = generate_build_command
            command << 'install'
            command << "--prefix=#{prefix}"
            command += installflags.flatten
            command
        end

        # Do the build in builddir
        def build
            unless File.file?(File.join(srcdir, 'setup.py'))
                raise ConfigException.new(self, 'build'),
                      "#{srcdir} contains no setup.py file"
            end

            command = generate_build_command
            command << '--force' if @forced
            progress_start 'building %s [progress not available]',
                           done_message: 'built %s' do
                run 'build', *command, working_directory: srcdir
            end
            Autobuild.touch_stamp(buildstamp)
        end

        # Install the result in prefix
        def install
            command = generate_install_command
            command << '--force' if @forced
            progress_start 'installing %s',
                           done_message: 'installed %s' do
                run 'install', *command, working_directory: srcdir
            end
            super
        end
    end
end
