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
	    exclude << Regexp.new("^#{Regexp.quote(installstamp)}")

            Autobuild.source_tree(srcdir) do |pkg|
		pkg.exclude.concat exclude
		exclude.freeze
	    end

            file installstamp => srcdir do 
                Autobuild.touch_stamp installstamp
            end
        end
    end
end


