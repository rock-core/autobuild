module Autobuild
    def self.make_is_gnumake?(path = Autobuild.tool(:make))
        @make_is_gnumake ||= Hash.new
        if @make_is_gnumake.has_key?(path)
            @make_is_gnumake[path]
        else
            result = `#{path} --version`
            @make_is_gnumake[path] = $?.success? &&
                (result.split("\n").first =~ /GNU Make/)
        end
    end

    def self.make_has_j_option?(path = Autobuild.tool(:make))
        make_is_gnumake?(path)
    end

    def self.make_has_gnumake_jobserver?(path = Autobuild.tool(:make))
        make_is_gnumake?(path)
    end

    def self.invoke_make_parallel(pkg, cmd_path = Autobuild.tool(:make))
        reserved = nil
        if make_has_j_option?(cmd_path) && pkg.parallel_build_level != 1
            if manager = Autobuild.parallel_task_manager
                job_server = manager.job_server
                if !make_has_gnumake_jobserver?(cmd_path) || (pkg.parallel_build_level != Autobuild.parallel_build_level)
                    reserved = pkg.parallel_build_level
                    job_server.get(reserved - 1) # We already have one token taken by autobuild itself
                    yield("-j#{pkg.parallel_build_level}")
                end
                yield("--jobserver-fds=#{job_server.rio.fileno},#{job_server.wio.fileno}", "-j")
            end
            yield("-j#{pkg.parallel_build_level}")
        else yield
        end
    ensure
        if reserved
            job_server.put(reserved)
        end
    end
    
    def self.make_subcommand(pkg, phase, *options, &block)
        invoke_make_parallel(pkg, Autobuild.tool(:make)) do |*make_parallel_options|
            pkg.run(phase, Autobuild.tool(:make), *make_parallel_options, *options, &block)
        end
    end
end
