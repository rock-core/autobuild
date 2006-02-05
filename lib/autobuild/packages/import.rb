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
        def initialize(target)
            super
            source_tree srcdir, installstamp
            file installstamp => srcdir do 
                touch_stamp installstamp
            end
        end
        def prepare; end
    end
end


