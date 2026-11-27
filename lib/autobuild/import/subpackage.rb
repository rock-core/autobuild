module Autobuild
    class Subpackage < Importer
        def initialize(source, options = {})
            @source = source

            parent_name = options[:parent]
            unless parent_name
              raise PackageException,
                    "Subpackage must provide a parent package."
            end

            @parent = Autoproj.workspace.manifest.package_definition_by_name(parent_name)
            unless @parent
              raise PackageException,
                    "Parent package #{parent_name} does not exist."
            end

            super(options.merge(repository_id: source))
        end

        # Does nothing, parent will do update
        def update(_package, _options = Hash.new)
            false
        end

        # Does nothing, parent will be checked out
        def checkout(package, _options = Hash.new)
            package.depends_on(@parent.autobuild)
        end

        # Does nothing, parent will do snapshot
        def snapshot(*)
            true
        end
    end

    def self.subpackage(source, options = {})
        Subpackage.new(source, options)
    end
end
