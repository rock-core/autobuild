$LOAD_PATH.unshift File.expand_path('..', File.dirname(__FILE__))
$LOAD_PATH << File.expand_path('../lib', File.dirname(__FILE__))
require 'test/unit'
require 'test/tools'
require 'autobuild/exceptions'
require 'autobuild/import/cvs'


class TC_CVSImport < Test::Unit::TestCase
    include Autobuild
    Package = Struct.new :srcdir, :name

    def setup
        Autobuild.logdir = "#{TestTools.tempdir}/log"
        FileUtils.mkdir_p(Autobuild.logdir)
    end
    
    def teardown
        TestTools.clean
    end

    def test_cvs
        TestTools.untar('cvsroot.tar')
        cvsroot = File.join(TestTools.tempdir, 'cvsroot')
        pkg_cvs = Package.new File.join(TestTools.tempdir, 'cvs'), 'cvs'

        # Make a checkout
        importer = Autobuild.cvs(cvsroot, 'cvs')
        importer.import(pkg_cvs)
        assert( File.exists?(File.join(pkg_cvs.srcdir, 'test')) )

        # Make an update
        importer.import(pkg_cvs)

        # Make an update fail because the repository does not exist anymore
        FileUtils.rm_rf cvsroot
        assert_raise(Autobuild::SubcommandFailed) { importer.import pkg_cvs }

        # Make a checkout fail because the repository does not exist anymore
        FileUtils.rm_rf pkg_cvs.srcdir
        assert_raise(Autobuild::SubcommandFailed) { importer.import pkg_cvs }

	# Recreate the repository, and make a checkout fail because the 
	# WC is not a CVS WC
        TestTools.untar('cvsroot.tar')
        FileUtils.mkdir pkg_cvs.srcdir
        assert_raise(Autobuild::ConfigException) { importer.import pkg_cvs }

	# Create two repositories, and make the update fail because the
	# WC is of the wrong source
	FileUtils.rm_rf pkg_cvs.srcdir
        importer.import(pkg_cvs)
	FileUtils.mv cvsroot, "#{cvsroot}.2"
        importer = Autobuild.cvs("#{cvsroot}.2", 'cvs')
        assert_raise(Autobuild::ConfigException) { importer.import pkg_cvs }
    end
end


