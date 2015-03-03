module Autobuild
    class << self
	# Configure the programs used by different packages
        attr_reader :programs
	# A cache of entries in programs to their resolved full path 
        #
        # @return [{String=>[String,String,String]}] the triplet (full path,
        #   tool name, value of ENV['PATH']). The last two values are used to
        #   invalidate the cache when needed
        #
        # @see tool_in_path
        attr_reader :programs_in_path

        # Get a given program, using its name as default value. For
	# instance
	#   tool('automake') 
	# will return 'automake' unless the autobuild script defined
	# another automake program in Autobuild.programs by doing
	#   Autobuild.programs['automake'] = 'automake1.9'
        def tool(name)
            programs[name.to_sym] || programs[name.to_s] || name.to_s
        end

        def find_in_path(file)
            path = ENV['PATH'].split(File::PATH_SEPARATOR).
                find { |dir| File.exist?(File.join(dir, file)) }
            if path
                return File.join(path, file)
            end
        end

        # Resolves the absolute path to a given tool
        def tool_in_path(name)
            path, path_name, path_env = programs_in_path[name]
            current = tool(name)
            if path_env != ENV['PATH'] || path_name != current
                # Delete the current entry given that it is invalid
                programs_in_path.delete(name)
                if current[0, 1] == "/"
                    # This is already a full path
                    path = current
                else
                    path = find_in_path(current)
                end

                if !path
                    raise ArgumentError, "tool #{name}, set to #{current}, can not be found in PATH=#{path_env}"
                end

                # Verify that the new value is a file and is executable
                if !File.file?(path)
                    raise ArgumentError, "tool #{name} is set to #{current}, but this resolves to #{path} which is not a file"
                elsif !File.executable?(path)
                    raise ArgumentError, "tool #{name} is set to #{current}, but this resolves to #{path} which is not executable"
                end
                programs_in_path[name] = [path, current, ENV['PATH']]
            end

            return path
        end
    end

    @programs = Hash.new
    @programs_in_path = Hash.new
end

