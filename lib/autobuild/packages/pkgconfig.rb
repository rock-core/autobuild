require 'autobuild/pkgconfig'

module Autobuild
    class InstalledPkgConfig < Package
	def initialize(name)
	    @pkgconfig = PkgConfig.new(name)
	    @prefix = @pkgconfig.prefix
	    super
	end

	def installstamp
	    std_stamp = super
	    if File.file?(std_stamp)
		std_stamp
	    else
		raise "#{name} is either not installed or has not been built by autobuild (#{std_stamp} not found)"
	    end
	end
    end
    def installed_pkgconfig(name, &block)
        InstalledPkgConfig.new(name, &block)
    end
end
 
