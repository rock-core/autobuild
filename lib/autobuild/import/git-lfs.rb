# Disable git-lfs at checkout time, we run install --local and pull later
Autobuild::Git.default_config['filter.lfs.smudge'] = 'git-lfs smudge --skip -- %f'
Autobuild::Git.default_config['filter.lfs.required'] = 'false'

module Autobuild
    def self.lfs_setup(importer, package)
        importer.run_git(package, 'lfs', 'install', '--force', '--local', '--skip-smudge')

        includes = importer.options.fetch(:lfs_include, '')
        if includes.empty?
            begin
                importer.run_git_bare(package, 'config', '--local',
                    '--unset', 'lfs.fetchinclude')
            rescue SubcommandFailed => e
                raise if e.status != 5
            end
        else
            importer.run_git_bare(package, 'config', '--local',
                'lfs.fetchinclude', includes)
        end

        excludes = importer.options.fetch(:lfs_exclude, '')
        if excludes.empty?
            begin
                importer.run_git_bare(package, 'config', '--local',
                    '--unset', 'lfs.fetchexclude')
            rescue SubcommandFailed => e
                raise if e.status != 5
            end
        else
            importer.run_git_bare(package, 'config', '--local',
                'lfs.fetchexclude', excludes)
        end

        if importer.options[:lfs] != false
            importer.run_git(package, 'lfs', 'pull', importer.remote_name)
        end
    end

    Git.add_post_hook(always: true) do |importer, package|
        wants_lfs = (importer.options[:lfs] != false && importer.uses_lfs?(package))
        if wants_lfs && !Git.lfs_installed?
            Autobuild.warn "#{package.name} uses git LFS but it is not installed, "\
                "files may be missing from checkout"
        end

        lfs_dir = File.join(package.importdir, '.git', 'lfs')
        Autobuild.lfs_setup(importer, package) if File.directory?(lfs_dir)
    end
end
