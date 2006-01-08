require 'autobuild/subcommand'
require 'autobuild/importer'

module Autobuild
    class SVN < Importer
        include ConfigMixin
        @config = {
            :program => 'svn',
            :up => '',
            :co => ''
        }

        def initialize(source, options)
            @source = source.to_a.join("/")

            options = config(options)
            @program = Config.programs
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
            SVN.new(source, options)
        end
    end
end

