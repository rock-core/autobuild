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

    def self.make_subcommand(pkg, phase, *options, &block)
        reserved = nil
        cmd_path = Autobuild.tool(:make)
        cmd = [cmd_path]
        if make_has_j_option?(cmd_path) && pkg.parallel_build_level != 1
            if manager = Autobuild.parallel_task_manager
                job_server = manager.job_server
                if !make_has_gnumake_jobserver?(cmd_path) || (pkg.parallel_build_level != Autobuild.parallel_build_level)
                    reserved = pkg.parallel_build_level
                    job_server.get(reserved - 1) # We already have one token taken by autobuild itself
                    cmd << "-j#{pkg.parallel_build_level}"
                else
                    cmd << "--jobserver-fds=#{job_server.rio.fileno},#{job_server.wio.fileno}" << "-j"
                end
            else
                cmd << "-j#{pkg.parallel_build_level}"
            end
        end

        cmd.concat(options)
        Subprocess.run(pkg, phase, *cmd, &block)

    ensure
        if reserved
            job_server.put(reserved)
        end
    end
end
