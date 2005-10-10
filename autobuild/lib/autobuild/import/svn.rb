require 'autobuild/subcommand'
require 'autobuild/importer'

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
            begin
                Subprocess.run(package.target, 'svn', @program, 'up', *@options_up)
            rescue SubcommandFailed => e
                raise ImportException.new(e), "failed to update #{package.target}"
            end
        }
    end

    def checkout(package)
        begin
            options = [ @program, 'co' ] + @options_co + [ @source, package.srcdir ]
            Subprocess.run(package.target, 'svn', *options)
        rescue SubcommandFailed => e
            raise ImportException.new(e), "failed to check out #{package.target}"
        end
    end
end

module Import
    def self.svn(source, options)
        SVNImporter.new(source, options)
    end
end

