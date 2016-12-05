# Disable git-lfs at checkout time, we run install --local and pull later 
Autobuild::Git.default_config['filter.lfs.smudge'] = 'git-lfs smudge --skip -- %f'
Autobuild::Git.default_config['filter.lfs.required'] = 'false'

module Autobuild
    Git.add_post_hook do |importer, package|
        lfs_dir = File.join(package.srcdir, '.git', 'lfs')
        if File.directory?(lfs_dir) && importer.options[:lfs] != false
            package.run 'import', Autobuild.tool(:git), 'lfs', 'install', '--local', '--skip-smudge',
                working_directory: package.importdir
            package.run 'import', Autobuild.tool(:git), 'lfs', 'pull', importer.remote_name,
                working_directory: package.importdir
        end
    end
end

