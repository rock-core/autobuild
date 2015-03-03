require 'autobuild/test'

class TC_CVSImport < Minitest::Test
    include Autobuild

    def setup
        super
        Autobuild.logdir = "#{tempdir}/log"
        FileUtils.mkdir_p(Autobuild.logdir)
    end
    
    def test_cvs
        Autobuild.verbose = true
        untar('cvsroot.tar')
        cvsroot = File.join(tempdir, 'cvsroot')
        pkg_cvs = Package.new 'cvs'
        pkg_cvs.srcdir = File.join(tempdir, 'cvs')

        # Make a checkout
        importer = Autobuild.cvs(cvsroot, module: 'cvs')
        importer.import(pkg_cvs)
        assert( File.exists?(File.join(pkg_cvs.srcdir, 'test')) )

        # Make an update
        importer.import(pkg_cvs)

        # Make an update fail because the repository does not exist anymore
        FileUtils.rm_rf cvsroot
        assert_raises(Autobuild::SubcommandFailed) { importer.import pkg_cvs }

        # Make a checkout fail because the repository does not exist anymore
        FileUtils.rm_rf pkg_cvs.srcdir
        assert_raises(Autobuild::SubcommandFailed) { importer.import pkg_cvs }

	# Recreate the repository, and make a checkout fail because the 
	# WC is not a CVS WC
        untar('cvsroot.tar')
        FileUtils.mkdir pkg_cvs.srcdir
        assert_raises(Autobuild::ConfigException) { importer.import pkg_cvs }

	# Create two repositories, and make the update fail because the
	# WC is of the wrong source
	FileUtils.rm_rf pkg_cvs.srcdir
        importer.import(pkg_cvs)
	FileUtils.mv cvsroot, "#{cvsroot}.2"
        importer = Autobuild.cvs("#{cvsroot}.2", module: 'cvs')
        assert_raises(Autobuild::ConfigException) { importer.import pkg_cvs }
    end
end


