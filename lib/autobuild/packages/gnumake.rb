module Autobuild
    def self.reset_gnumake_detection
        @make_is_gnumake = Hash.new
        @gnumake_version = Hash.new
    end

    def self.ensure_gnumake_detected(pkg, path = Autobuild.tool(:make))
        @make_is_gnumake ||= Hash.new
        @gnumake_version ||= Hash.new
        return @make_is_gnumake[path] if @make_is_gnumake.key?(path)

        begin
            gnumake_version_string = pkg.run('prepare', path, '--version')
        rescue Autobuild::SubcommandFailed
            @make_is_gnumake[path] = false
            return
        end

        gnumake_match = /^GNU Make[^\d]+(\d[\d.]+)/.match(gnumake_version_string.first)
        unless gnumake_match
            @make_is_gnumake[path] = false
            return
        end

        @gnumake_version[path] = Gem::Version.new(gnumake_match[1])
        @make_is_gnumake[path] = true
    end

    def self.make_is_gnumake?(pkg, path = Autobuild.tool(:make))
        ensure_gnumake_detected(pkg, path)
    end

    class NotGNUMake < RuntimeError
    end

    def self.gnumake_version(pkg, path = Autobuild.tool(:make))
        if ensure_gnumake_detected(pkg, path)
            @gnumake_version.fetch(path)
        else
            raise NotGNUMake, "either #{path} is not a GNU Make or it does not have "\
                              "the expected version string"
        end
    end

    def self.make_has_j_option?(pkg, path = Autobuild.tool(:make))
        make_is_gnumake?(pkg, path)
    end

    def self.make_has_gnumake_jobserver?(pkg, path = Autobuild.tool(:make))
        make_is_gnumake?(pkg, path)
    end

    GNUMAKE_JOBSERVER_AUTH_VERSION = Gem::Version.new("4.2.0")

    def self.gnumake_jobserver_option(job_server, pkg, path = Autobuild.tool(:make))
        jobserver_fds_arg = "#{job_server.rio.fileno},#{job_server.wio.fileno}"

        version = gnumake_version(pkg, path)
        if version >= GNUMAKE_JOBSERVER_AUTH_VERSION
            ["--jobserver-auth=#{jobserver_fds_arg}"]
        else
            ["--jobserver-fds=#{jobserver_fds_arg}", "-j"]
        end
    end

    def self.invoke_make_parallel(pkg, cmd_path = Autobuild.tool(:make))
        reserved = nil
        return yield unless make_has_j_option?(pkg, cmd_path)

        manager = Autobuild.parallel_task_manager
        return yield("-j#{pkg.parallel_build_level}") unless manager

        job_server = manager.job_server

        specific_parallel_level = (
            pkg.parallel_build_level != Autobuild.parallel_build_level
        )
        if !make_has_gnumake_jobserver?(pkg, cmd_path) || specific_parallel_level
            reserved = pkg.parallel_build_level
            # Account for the one token autobuild uses
            begin
                job_server.get(reserved - 1)
                return yield("-j#{pkg.parallel_build_level}")
            ensure
                job_server.put(reserved - 1)
            end
        end

        options = gnumake_jobserver_option(job_server, pkg, cmd_path)
        yield(*options)
    end

    def self.make_subcommand(pkg, phase, *options, &block)
        invoke_make_parallel(pkg, Autobuild.tool(:make)) do |*make_parallel_options|
            pkg.run(phase, Autobuild.tool(:make),
                    *make_parallel_options, *options, &block)
        end
    end
end
