require 'autobuild/timestamps'
require 'autobuild/package'

class ImporterPackage < Package
    def installstamp
        "#{srcdir}/#{STAMPFILE}"
    end
    def initialize(target, options)
        super(target, options)
        source_tree srcdir, installstamp
        file installstamp => srcdir do 
            touch_stamp installstamp
        end
    end

    factory :import, ImporterPackage
end


