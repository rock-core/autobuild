require 'rubygems/version'

module Autobuild
    def self.make_is_gnumake?(pkg, path = Autobuild.tool(:make))
        @make_is_gnumake ||= Hash.new
        @gnumake_version ||= Hash.new
        if @make_is_gnumake.key?(path)
            @make_is_gnumake[path]
        else
            begin
                result = pkg.run('prepare', path, '--version')
                @make_is_gnumake[path] = (result.first =~ /GNU Make/)
                @gnumake_version[path] = Gem::Version.new(result.first.scan(/[\d.]+/)[0])
            rescue Autobuild::SubcommandFailed
                @make_is_gnumake[path] = false
            end
        end
    end

    def self.make_has_j_option?(pkg, path = Autobuild.tool(:make))
        make_is_gnumake?(pkg, path)
    end

    def self.make_has_gnumake_jobserver?(pkg, path = Autobuild.tool(:make))
        make_is_gnumake?(pkg, path)
    end

    def self.invoke_make_parallel(pkg, cmd_path = Autobuild.tool(:make))
        reserved = nil
        if make_has_j_option?(pkg, cmd_path) && pkg.parallel_build_level != 1
            if (manager = Autobuild.parallel_task_manager)
                job_server = manager.job_server

                specific_parallel_level = (pkg.parallel_build_level !=
                    Autobuild.parallel_build_level)
                if !make_has_gnumake_jobserver?(pkg, cmd_path) || specific_parallel_level
                    reserved = pkg.parallel_build_level
                    # Account for the one token autobuild uses
                    job_server.get(reserved - 1)
                    yield("-j#{pkg.parallel_build_level}")
                end

                jobserver_fds_arg = "#{job_server.rio.fileno},#{job_server.wio.fileno}"

                if @gnumake_version[cmd_path] >= Gem::Version.new("4.2.0")
                    yield("--jobserver-auth=#{jobserver_fds_arg}", "-j")
                else
                    yield("--jobserver-fds=#{jobserver_fds_arg}", "-j")
                end
            end
            yield("-j#{pkg.parallel_build_level}")
        else yield
        end
    ensure
        job_server.put(reserved) if reserved
    end

    def self.make_subcommand(pkg, phase, *options, &block)
        invoke_make_parallel(pkg, Autobuild.tool(:make)) do |*make_parallel_options|
            pkg.run(phase, Autobuild.tool(:make),
                *make_parallel_options, *options, &block)
        end
    end
end
