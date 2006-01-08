module Autobuild
    ## Adds an element to a path-like variable
    def self.pathvar(path, varname)
        if File.directory?(path)
            oldpath = ENV[varname]
            if oldpath.empty?
                ENV[varname] = path
            else
                ENV[varname] = "#{path}:#{oldpath}"
            end
        end
    end

    ## Updates the environment when a new prefix has been added
    # TODO: modularize that
    def self.update_environment(newprefix)
        pathvar("#{newprefix}/bin", 'PATH')
        pathvar("#{newprefix}/lib/pkgconfig", 'PKG_CONFIG_PATH')
    end
end

