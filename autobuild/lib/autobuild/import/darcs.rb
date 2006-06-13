require 'autobuild/config'
require 'autobuild/subcommand'
require 'autobuild/importer'

module Autobuild
    class DarcsImporter < Importer
        def initialize(source, options = {})
            @source   = source
            @program  = Autobuild.tool('darcs')
            super(options)
        end
        
        private

        def update(package)
	    Subprocess.run(package.name, :import, @program, 
	       'pull', '--all', "--repodir=#{package.srcdir}", '--set-scripts-executable', @source)
        end

        def checkout(package)
	    Subprocess.run(package.name, :import, @program, 
	       'get', '--set-scripts-executable', @source, package.srcdir)
        end
    end

    def self.darcs(source, options = {})
        DarcsImporter.new(source, options)
    end
end

