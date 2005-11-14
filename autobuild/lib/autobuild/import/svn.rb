require 'autobuild/subcommand'
require 'autobuild/importer'

module Autobuild
    class SVNImporter < Importer
        def initialize(source, options)
            @source = source.to_a.join("/")

            @program = ($PROGRAMS[:svn] || 'svn')
            @options_up = options[:svnup].to_a
            @options_co = options[:svnco].to_a
            super(options)
        end

        private

        def update(package)
            Dir.chdir(package.srcdir) {
                Subprocess.run(package.target, :import, @program, 'up', *@options_up)
            }
        end

        def checkout(package)
            options = [ @program, 'co' ] + @options_co + [ @source, package.srcdir ]
            Subprocess.run(package.target, :import, *options)
        end
    end

    module Import
        def self.svn(source, options)
            SVNImporter.new(source, options)
        end
    end
end

