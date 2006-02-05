require 'autobuild/subcommand'
require 'autobuild/importer'

module Autobuild
    class SVN < Importer
        @config = {
            :program => 'svn',
            :up => '',
            :co => ''
        }

        def initialize(source, options)
            @source = source.to_a.join("/")

            options = config(options)
            @program = Autobuild.programs
            @options_up = Array[*options[:svnup]]
            @options_co = Array[*options[:svnco]]
            super(options)
        end

        private

        def update(package)
            Dir.chdir(package.srcdir) {
                Subprocess.run(package.name, :import, @program, 'up', *@options_up)
            }
        end

        def checkout(package)
            options = [ @program, 'co' ] + @options_co + [ @source, package.srcdir ]
            Subprocess.run(package.name, :import, *options)
        end
    end

    module Import
        def self.svn(source, options)
            SVN.new(source, options)
        end
    end
end

