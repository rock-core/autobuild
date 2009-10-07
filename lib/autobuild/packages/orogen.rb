module Autobuild
    def self.orogen(opts, &proc)
        Orogen.new(opts, &proc)
    end

    class Orogen < CMake
        class << self
            attr_accessor :corba
        end

        attr_accessor :corba

        attr_accessor :orogen_file
        def initialize(*args, &config)
            @corba       = Orogen.corba
            super

            @orogen_file ||= "#{File.basename(name)}.orogen"

            # Find out where orogen is, and make sure the configurestamp depend
            # on it. Ignore if orogen is too old to have a --base-dir option
            orogen_root = File.join(`orogen --base-dir`.chomp, 'orogen')
            if !orogen_root.empty?
                file genstamp => Autobuild.source_tree(orogen_root)
            end

            file configurestamp => genstamp
            file genstamp => File.join(srcdir, orogen_file) do
                regen
            end
        end

        def depends_on(*packages)
            super

            packages.each do |p|
                file genstamp => Package[p].installstamp
            end
        end

        def genstamp; File.join(srcdir, '.orogen', 'orogen-stamp') end

        def regen
            cmdline = [Autobuild.tool('orogen')]
            cmdline << '--corba' if corba
            cmdline << orogen_file

            Autobuild.progress "generating oroGen project #{name}"
            Dir.chdir(srcdir) do
                Subprocess.run name, 'orogen', *cmdline
                Autobuild.touch_stamp genstamp
            end
        end
    end
end

