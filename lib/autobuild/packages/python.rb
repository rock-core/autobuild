require 'autobuild/configurable'
require 'open3'

# Main Autobuild module
module Autobuild
    def self.python(opts, &proc)
        Python.new(opts, &proc)
    end

    # Handler class to build python-based packages
    class Python < Configurable
        attr_accessor :buildflags, :installflags

        def configurestamp
            "#{builddir}/configure-autobuild-stamp"
        end

        def initialize(options)
            @buildflags = []
            @installflags = []
            super
        end

        def install_mode?
            File.file?(File.join(srcdir, 'setup.py'))
        end

        def prepare_for_forced_build
            super
            @forced = true
        end

        def generate_build_command
            command = %w[python setup.py]
            command << "egg_info"
            command << "--egg-base=#{builddir}"
            command << "build"
            command << "--build-base=#{builddir}"
            command += buildflags.flatten
            command
        end

        def generate_install_command
            command = generate_build_command
            command << 'install'
            command << "--prefix=#{prefix}"
            command << "--record=#{builddir}/install.log"
            command << "--single-version-externally-managed"
            command += installflags.flatten
            command
        end

        def python_path
            begin
                env = Autobuild.env.resolved_env.merge({ 'PYTHONUSERBASE' => prefix })
                _, output, _, ret = Open3.popen3(env, 'python -m site --user-site')
            rescue Exception => e
                raise "Unable to set PYTHONPATH: #{e.message}"
            end

            if ret.value.success?
                output.read.chomp
            else
                raise 'Unable to set PYTHONPATH: user site directory disabled?'
            end
        end

        # Do the build in builddir
        def build
            return unless install_mode?

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
            return unless install_mode?

            command = generate_install_command
            command << '--force' if @forced
            progress_start 'installing %s',
                           done_message: 'installed %s' do
                run 'install', *command, working_directory: srcdir
            end
            super
        end

        def update_environment
            super
            path = install_mode? ? python_path : srcdir
            env_add_path 'PYTHONPATH', path
        end
    end
end
