require 'autobuild/subcommand' 
require 'autobuild/importer'

class SVNImporter < Importer
    def initialize(source, options)
        @source = source.to_a.join("/")

        @program = ($PROGRAMS[:svn] || 'svn')
        @up = options[:svnup]
        @co = options[:svnco]
    end

    private

    def update(package)
        Dir.chdir(package.srcdir) {
            begin
                subcommand(package.target, 'svn', "#{program} up #{@up}")
            rescue SubcommandFailed => e
                raise ImportException.new(e), "failed to update #{modulename}"
            end
        }
    end

    def checkout(package)
        begin
            subcommand(package.target, 'svn', "#{program} co #{@co} #{@source} #{package.srcdir}")
        rescue SubcommandFailed => e
            raise ImportException.new(e), "failed to check out #{modulename}"
        end
    end
end

module Import
    def self.svn(source, options)
        SVNImporter.new(source, options)
    end
end

