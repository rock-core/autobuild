module Autobuild
    ## Adds an element to a path-like variable
    def self.pathvar(path, varname)
        if File.directory?(path)
            oldpath = ENV[varname]
            if oldpath.nil? || oldpath.empty?
                ENV[varname] = path
            elsif ENV[varname] !~ /(^|:)#{Regexp.quote(path)}($|:)/
                ENV[varname] = "#{path}:#{oldpath}"
            end
        end
    end

    ## Updates the environment when a new prefix has been added
    # TODO: modularize that
    def self.update_environment(newprefix)
        pathvar("#{newprefix}/bin", 'PATH')
        pathvar("#{newprefix}/lib/pkgconfig", 'PKG_CONFIG_PATH')
        pathvar("#{newprefix}/lib/ruby/1.8", 'RUBYLIB')

        require 'rbconfig'
        ruby_arch = File.basename(Config::CONFIG['archdir'])
        pathvar("#{newprefix}/lib/ruby/1.8/#{ruby_arch}", 'RUBYLIB')
    end
end

