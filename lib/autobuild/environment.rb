def pathvar(path, varname)
    if File.directory?(path)
        oldpath = ENV[varname]
        if oldpath.empty?
            ENV[varname] = path
        else
            ENV[varname] = "#{path}:#{oldpath}"
        end
    end
end

def update_environment(newprefix)
    pathvar("#{newprefix}/bin", 'PATH')
    pathvar("#{newprefix}/lib/pkgconfig", 'PKG_CONFIG_PATH')
end

