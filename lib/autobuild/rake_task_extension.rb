module Autobuild
    module RakeTaskExtension
        def initialize(*, **)
            super
            @disabled = false
        end

        def already_invoked?
            @already_invoked
        end

        attr_writer :already_invoked

        def disabled?
            @disabled
        end

        def disabled!
            disable
        end

        def disable
            @disabled = true
        end
    end
end

class Rake::Task # rubocop:disable Style/ClassAndModuleChildren
    include Autobuild::RakeTaskExtension
end
