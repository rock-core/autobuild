$LOAD_PATH << File.expand_path('../lib', File.dirname(__FILE__))
$LOAD_PATH << File.dirname(__FILE__)
require 'test/unit'
require 'tools'
require 'autobuild/import/cvs'
require 'autobuild/import/svn'

class TC_Import < Test::Unit::TestCase
    Package = Struct.new :srcdir, :target

    def setup
        $PROGRAMS = {}
        $UPDATE = true
        $LOGDIR = "#{TestTools.tempdir}/log"
        FileUtils.mkdir_p($LOGDIR)

    end
    
    def teardown
        $PROGRAMS = nil
        $UPDATE = true
        $LOGDIR = nil
        TestTools.clean
    end

    def test_cvs
        TestTools.untar('cvsroot.tar')
        cvsroot = File.join(TestTools.tempdir, 'cvsroot')
        pkg_cvs = Package.new File.join(TestTools.tempdir, 'cvs'), :cvs

        # Make a checkout
        importer = Import.cvs [ cvsroot, 'cvs' ], {}
        importer.import(pkg_cvs)
        assert( File.exists?(File.join(pkg_cvs.srcdir, 'test')) )

        # Make an update
        importer.import(pkg_cvs)

        # Make an update fail
        FileUtils.rm_rf cvsroot
        assert_raise(ImportException) { importer.import pkg_cvs }

        # Make a checkout fail
        FileUtils.rm_rf pkg_cvs.srcdir
        assert_raise(ImportException) { importer.import pkg_cvs }
    end

    def test_svn
        TestTools.untar('svnroot.tar')
        svnrepo = File.join(TestTools.tempdir, 'svnroot')
        svnroot = "file:///#{svnrepo}"
        pkg_svn = Package.new File.join(TestTools.tempdir, 'svn'), :svn

        # Make a checkout with a splitted URL
        importer = Import.svn [ svnroot, 'svn' ], {}
        importer.import(pkg_svn)
        assert( File.exists?(File.join(pkg_svn.srcdir, 'test')) )

        # Make a checkout with an URL as a string
        FileUtils.rm_rf pkg_svn.srcdir
        importer = Import.svn File.join(svnroot, 'svn'), {}
        importer.import(pkg_svn)
        assert( File.exists?(File.join(pkg_svn.srcdir, 'test')) )

        # Make an update
        importer.import(pkg_svn)

        # Make an update fail
        FileUtils.rm_rf svnrepo
        assert_raise(ImportException) { importer.import(pkg_svn) }

        # Make a checkout fail
        FileUtils.rm_rf pkg_svn.srcdir
        assert_raise(ImportException) { importer.import(pkg_svn) }
    end
end
 
