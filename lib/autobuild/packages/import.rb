require 'autobuild/timestamps'
require 'autobuild/package'

module Autobuild
    def self.import(spec, &proc)
        ImporterPackage.new(spec, &proc)
    end
    
    class ImporterPackage < Package
        def installstamp
            "#{srcdir}/#{STAMPFILE}"
        end
	
	attr_reader :exclude

        def initialize(*args)
	    @exclude = []
            super
        end

        def prepare
            super

            exclude = self.exclude.dup
	    exclude << Regexp.new("^#{Regexp.quote(installstamp)}")
            if doc_dir
                exclude << Regexp.new("^#{doc_dir}")
            end

            Autobuild.source_tree(srcdir) do |pkg|
		pkg.exclude.concat exclude
		exclude.freeze
	    end

            file installstamp => srcdir
        end
    end
end


