module Autobuild
    def self.dummy(spec)
        ImporterPackage.new(spec)
    end

    class DummyPackage < Package
        def installstamp
            "#{srcdir}/#{STAMPFILE}"
        end
	
        def initialize(*args)
            super
        end

        def import
        end

        def prepare
            %w{import prepare build doc}.each do |phase|
                Rake.task("#{name}-#{phase}")
                t = Rake::Task["#{name}-#{phase}"]
                def t.needed?; false end
            end
            Rake.task(installstamp)
            t = Rake::Task[installstamp]
            def t.needed?; false end
        end
    end
end
    

