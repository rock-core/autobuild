module Autobuild
    module RakeTaskExtension
        def already_invoked?
            !!@already_invoked
        end

        def already_invoked=(value)
            @already_invoked = value
        end

        def disable!
            @already_invoked = true

            def self.needed?
                false
            end
        end
    end
end
class Rake::Task
    include Autobuild::RakeTaskExtension
end
