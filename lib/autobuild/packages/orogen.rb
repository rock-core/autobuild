module Autobuild
    def self.orogen(opts, &proc)
        Orogen.new(opts, &proc)
    end


    # This discards everything but the calls to import_types_from,
    # using_task_library and using_toolkit. This is used to automatically
    # discover the dependencies without resorting to an actual build
    class FakeOrogenEnvironment
        class BlackHole
            def initialize(*args)
            end
            def method_missing(*args)
                self
            end
            def self.method_missing(*args)
                self
            end
            def self.const_missing(*args)
                self
            end
        end
        StaticDeployment = BlackHole
        StaticDeployment::Logger = BlackHole
        TaskContext = BlackHole

        class FakeDeployment
            attr_reader :env
            def initialize(env, name)
                @env = env
                env.provides << "pkgconfig/orogen-#{name}"
            end
            def add_default_logger
                env.using_task_library 'logger'
                BlackHole
            end
            def task(*args)
                method_missing(*args)
            end
            def const_missing(*args)
                BlackHole
            end
            def method_missing(*args)
                BlackHole
            end
            def self.const_missing(*args)
                BlackHole
            end
        end

        attr_reader :orogen_file
        attr_reader :base_dir
        attr_reader :project_name, :dependencies, :provides
        def self.load(pkg, file)
            FakeOrogenEnvironment.new(pkg).load(file)
        end

        # The Autobuild::Orogen instance we are working for
        attr_reader :pkg

        def initialize(pkg)
            @pkg = pkg
            @dependencies = Array.new
            @provides = Array.new
        end

        def load(file)
            @orogen_file = file
            @base_dir = File.dirname(file)
            Kernel.eval(File.read(file), binding)
            self
        end

        def name(name)
            @project_name = name
            nil
        end
        def using_library(*names)
            @dependencies.concat(names)
            nil
        end
        def import_types_from(name)
            if !File.file?(File.join(base_dir, name)) && name.downcase !~ /\.(hh|hpp|h)/
                using_toolkit name
            end
        end
        def using_toolkit(*names)
            names = names.map { |n| "#{n}-toolkit-#{pkg.orocos_target}" }
            @dependencies.concat(names)
            nil
        end
        def using_task_library(*names)
            names = names.map { |n| "#{n}-tasks-#{pkg.orocos_target}" }
            @dependencies.concat(names)
            nil
        end

        def static_deployment(name = nil, &block)
            deployment("test_#{project_name}", &block)
        end
        def deployment(name, &block)
            deployment = FakeDeployment.new(self, name)
            deployment.instance_eval(&block) if block
            deployment
        end

        def self.const_missing(*args)
            BlackHole
        end
        def const_missing(*args)
            BlackHole
        end
        def method_missing(*args)
            BlackHole
        end
    end

    # This class represents packages generated by orogen. oroGen is a
    # specification and code generation tool for the Orocos/RTT integration
    # framework. See http://doudou.github.com/orogen for more information.
    #
    # This class extends the CMake package class to handle the code generation
    # step. Moreover, it will load the orogen specification and automatically
    # add the relevant pkg-config dependencies as dependencies.
    #
    # This requires that the relevant packages define the pkg-config definitions
    # they install in the pkgconfig/ namespace. It means that a "driver/camera"
    # package (for instance) that installs a "camera.pc" file will have to
    # provide the "pkgconfig/camera" virtual package. This is done automatically
    # by the CMake package handler if the source contains a camera.pc.in file,
    # but can also be done manually with a call to Package#provides:
    #
    #   pkg.provides "pkgconfig/camera"
    #
    class Orogen < CMake
        class << self
            attr_accessor :corba
        end

        @orocos_target = nil
        def self.orocos_target
            user_target = ENV['OROCOS_TARGET']
            if @orocos_target
                @orocos_target.dup
            elsif user_target && !user_target.empty?
                user_target
            else
                'gnulinux'
            end
        end

        def self.orogen_bin
            if @orogen_bin
                @orogen_bin
            else
                program_name = Autobuild.tool('orogen')
                if orogen_path = ENV['PATH'].split(':').find { |p| File.file?(File.join(p, program_name)) }
                    @orogen_bin = File.join(orogen_path, program_name)
                else
                    program_name
                end
            end
        end

        def self.orogen_root
            if @orogen_root
                @orogen_root
            elsif orogen_bin = self.orogen_bin
                @orogen_root = File.expand_path('../lib', File.dirname(orogen_bin))
            end
        end

        attr_writer :orocos_target
        def orocos_target
            if @orocos_target.nil?
                Orogen.orocos_target
            else
                @orocos_target
            end
        end

        attr_reader :orogen_spec

        attr_writer :corba
        def corba
            @corba || (@corba.nil? && Orogen.corba)
        end

        attr_accessor :orogen_file
        def initialize(*args, &config)
            @corba       = Orogen.corba
            super

            @orocos_target = nil
            @orogen_file ||= "#{File.basename(name)}.orogen"
        end

        def import
            super

            @orogen_spec = FakeOrogenEnvironment.load(self, File.join(srcdir, orogen_file))
            provides "pkgconfig/#{orogen_spec.project_name}-toolkit-#{orocos_target}"
            provides "pkgconfig/#{orogen_spec.project_name}-tasks-#{orocos_target}"
            orogen_spec.provides.each do |name|
                provides name
            end
        end

        def prepare
            super

            dependencies.each do |p|
                file genstamp => Package[p].installstamp
            end
            # Check if someone provides the pkgconfig/orocos-rtt-TARGET package,
            # and if so add it into our dependency list
            if rtt = Autobuild::Package["pkgconfig/orocos-rtt-#{orocos_target}"]
                if Autobuild.verbose
                    STDERR.puts "orogen: found #{rtt.name} which provides the RTT"
                end
                depends_on rtt.name
            end

            # If required, load the component's specification and add
            # dependencies based on the orogen specification.
            orogen_spec.dependencies.each do |pkg_name|
                target = "pkgconfig/#{pkg_name}"
                if Autobuild::Package[target]
                    depends_on target
                end
            end

            # Check if there is an orogen package registered. If it is the case,
            # simply depend on it. Otherwise, look out for orogen --base-dir
            if Autobuild::Package['orogen']
                depends_on "orogen"
            else
                # Find out where orogen is, and make sure the configurestamp depend
                # on it. Ignore if orogen is too old to have a --base-dir option
                if orogen_root = self.class.orogen_root
                    orogen_root = File.join(orogen_root, 'orogen')
                    file genstamp => Autobuild.source_tree(orogen_root)
                end
            end

            file configurestamp => genstamp
            file genstamp => File.join(srcdir, orogen_file) do
                regen
            end

            with_doc
        end
        def genstamp; File.join(srcdir, '.orogen', 'orogen-stamp') end

        def regen
            cmdline = [Autobuild.tool('ruby'), self.class.orogen_bin]
            cmdline << '--corba' if corba
            cmdline << orogen_file

            progress "generating oroGen project %s"
            Dir.chdir(srcdir) do
                Subprocess.run self, 'orogen', *cmdline
                Autobuild.touch_stamp genstamp
            end
        end
    end
end

