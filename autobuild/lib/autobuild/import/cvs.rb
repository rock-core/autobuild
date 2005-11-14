require 'autobuild/subcommand'
require 'autobuild/importer'

module Autobuild
    class CVSImporter < Importer
        def initialize(root, name, options)
            @root = root
            @module = name

            @program    = ($PROGRAMS[:cvs] || 'cvs')
            @options_up = ( options[:cvsup] || '-dP' ).to_a
            @options_co = ( options[:cvsco] || '-P' ).to_a
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

