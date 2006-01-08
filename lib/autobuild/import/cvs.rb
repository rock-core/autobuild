require 'autobuild/config'
require 'autobuild/subcommand'
require 'autobuild/importer'

module Autobuild
    class Config
        config_option '-dP', :cvsup
        config_option '-P', :cvsco
    end

    class CVSImporter < Importer
        def initialize(root, name, options)
            @root = root
            @module = name

            @program    = Config.tool('cvs')
            @options_up = options[:cvsup] || Config.cvsup
            @options_co = options[:cvsco] || Config.cvsco
            super(options)
        end
        
        def modulename
            @module
        end

        private

        def update(package)
            Dir.chdir(package.srcdir) {
                Subprocess.run(package.target, :import, @program, 'up', *@options_up)
            }
        end

        def checkout(package)
            head, tail = File.split(package.srcdir)
            cvsroot = @root
               
            FileUtils.mkdir_p(head) if !File.directory?(head)
            Dir.chdir(head) {
                options = [ @program, '-d', cvsroot, 'co', '-d', tail ] + @options_co + [ modulename ]
                Subprocess.run(package.target, :import, *options)
            }
        end
    end

    module Import
        def self.cvs(source, package_options)
            CVSImporter.new(source[0], source[1], package_options)
        end
    end
end

