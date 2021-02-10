require 'autobuild/pkgconfig'

module Autobuild
    class InstalledPkgConfig < Package
        attr_reader :pkgconfig, :prefix

        def initialize(name)
            @pkgconfig = PkgConfig.new(name)
            @prefix    = @pkgconfig.prefix
            super
        end

        def installstamp
            std_stamp = super
            return std_stamp if File.file?(std_stamp)

            pcfile = File.join(pkgconfig.prefix, "lib", "pkgconfig", "#{name}.pc")
            unless File.file?(pcfile)
                raise "cannot find the .pc file for #{name}, tried #{pcfile}"
            end

            pcfile
        end
    end

    def self.installed_pkgconfig(name, &block)
        InstalledPkgConfig.new(name, &block)
    end
end
