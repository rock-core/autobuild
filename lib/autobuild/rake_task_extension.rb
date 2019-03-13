module Autobuild
    module RakeTaskExtension
        def already_invoked?
            @already_invoked
        end

        attr_writer :already_invoked

        def disable!
            @already_invoked = true
            singleton_class.class_eval do
                define_method(:needed?) { false }
            end
        end
    end
end
class Rake::Task # rubocop:disable Style/ClassAndModuleChildren
    include Autobuild::RakeTaskExtension
end
