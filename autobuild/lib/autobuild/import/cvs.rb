require 'autobuild/config'
require 'autobuild/subcommand'
require 'autobuild/importer'

module Autobuild
    class CVSImporter < Importer
        def initialize(root, name, options = {})
            @root = root
            @module = name

            @program    = Autobuild.tool('cvs')
            @options_up = options[:cvsup] || '-dP'
            @options_up = Array[*@options_up]
            @options_co = options[:cvsco] || '-P'
            @options_co = Array[*@options_co]
            super(options)
        end
        
        def modulename
            @module
        end

        private

        def update(package)
            Dir.chdir(package.srcdir) {
                Subprocess.run(package.name, :import, @program, 'up', *@options_up)
            }
        end

        def checkout(package)
            head, tail = File.split(package.srcdir)
            cvsroot = @root
               
            FileUtils.mkdir_p(head) if !File.directory?(head)
            Dir.chdir(head) {
                options = [ @program, '-d', cvsroot, 'co', '-d', tail ] + @options_co + [ modulename ]
                Subprocess.run(package.name, :import, *options)
            }
        end
    end

    def self.cvs(repo, name, package_options = {})
        CVSImporter.new(repo, name, package_options)
    end
end

