require 'autobuild/subcommand'
require 'autobuild/importer'

class CVSImporter < Importer
    def initialize(root, name, options)
        @root = root
        @module = name

        @program = ($PROGRAMS[:cvs] || 'cvs')
        @up = (options[:cvsup] || '-dP')
        @co = (options[:cvsco] || '-P')
        super(options)
    end
    
    def modulename
        @module
    end

    private

    def update(package)
        Dir.chdir(package.srcdir) {
            begin
                subcommand(package.target, 'cvs', @program, 'up' , @up)
            rescue SubcommandFailed => e
                raise ImportException.new(e), "failed to update #{modulename}"
            end
        }
    end

    def checkout(package)
        head, tail = File.split(package.srcdir)
        cvsroot = @root
           
        FileUtils.mkdir_p(head) if !File.directory?(head)
        Dir.chdir(head) {
            begin
                subcommand(package.target, 'cvs', @program, '-d', cvsroot, 'co', @co, '-d', tail, modulename)
            rescue SubcommandFailed => e
                raise ImportException.new(e), "failed to check out #{modulename}"
            end
        }
    end
end

module Import
    def self.cvs(source, package_options)
        CVSImporter.new(source[0], source[1], package_options)
    end
end

