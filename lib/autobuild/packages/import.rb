module Autobuild
    def self.import(spec, &proc)
        ImporterPackage.new(spec, &proc)
    end

    class ImporterPackage < Package
        attr_reader :exclude

        def initialize(*args)
            @exclude = []
            super
        end

        def prepare
            super

            exclude = self.exclude.dup
            exclude << Regexp.new("^#{Regexp.quote(installstamp)}")
            exclude << Regexp.new("^#{Regexp.quote(doc_dir)}") if doc_dir

            source_tree(srcdir) do |pkg|
                pkg.exclude.concat exclude
                exclude.freeze
            end

            file installstamp => srcdir
        end
    end
end
