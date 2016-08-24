module Autobuild
    Git.add_post_hook do |importer, package|
        if File.join(package.srcdir, '.git', 'lfs')

            package.run 'import', Autobuild.tool(:git), 'lfs', 'pull', importer.remote_name,
                working_directory: package.srcdir
        end
    end
end

