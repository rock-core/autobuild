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

            task "#{name}-prepare" => genstamp
            file genstamp => File.join(srcdir, orogen_file) do
                regen
            end
        end

        def genstamp; File.join(srcdir, '.orogen', 'orogen-stamp') end

        def regen
            cmdline = [Autobuild.tool('orogen')]
            cmdline << '--corba' if corba
            cmdline << orogen_file

            Dir.chdir(srcdir) do
                Subprocess.run name, 'orogen', *cmdline
                touch_stamp genstamp
            end
        end
    end
end

