require 'autobuild/test'

class TC_SVNImport < Minitest::Test
    include Autobuild

    def setup
        super
        Autobuild.logdir = "#{tempdir}/log"
        FileUtils.mkdir_p(Autobuild.logdir)
    end
    
    def test_svn
        untar('svnroot.tar')
        svnrepo = File.join(tempdir, 'svnroot')
        svnroot = "file://#{svnrepo}/svn"
        pkg_svn = Package.new 'svn'
        pkg_svn.srcdir = File.join(tempdir, 'svn')

        # Make a checkout with a splitted URL
        importer = Autobuild.svn(svnroot)
        importer.import(pkg_svn)
        assert( File.exists?(File.join(pkg_svn.srcdir, 'test')) )

        # Make an update
        importer.import(pkg_svn)

        # Make an update fail because the repository does not exist
        FileUtils.rm_rf svnrepo
        assert_raises(SubcommandFailed) { importer.import(pkg_svn) }

        # Make a checkout fail because the repository does not exist
        FileUtils.rm_rf pkg_svn.srcdir
        assert_raises(SubcommandFailed) { importer.import(pkg_svn) }

	# Recreate the repository and try to update a non-svn directory
        untar('svnroot.tar')
	FileUtils.mkdir pkg_svn.srcdir
        assert_raises(SubcommandFailed) { importer.import(pkg_svn) }

	# Try to update a WC which is of a different repository
	FileUtils.rmdir pkg_svn.srcdir
	importer.import(pkg_svn)
	FileUtils.mv svnrepo, "#{svnrepo}.2"
        importer = Autobuild.svn("file://#{svnrepo}.2/svn")
        assert_raises(ConfigException) { importer.import(pkg_svn) }
    end

end
 
