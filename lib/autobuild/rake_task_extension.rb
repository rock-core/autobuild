module Autobuild
    module RakeTaskExtension
        def already_invoked?
            !!@already_invoked
        end

        def disable!
            @already_invoked = true
            def self.needed?; false end
        end
    end
end
class Rake::Task
    include Autobuild::RakeTaskExtension
end
