$LOAD_PATH.unshift File.expand_path('..', File.dirname(__FILE__))
$LOAD_PATH << File.expand_path('../lib', File.dirname(__FILE__))
require 'test/unit'
require 'test/tools'
require 'autobuild/import/cvs'
require 'autobuild/import/svn'
require 'autobuild/import/tar'
include Autobuild

class TC_SVNImport < Test::Unit::TestCase
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
        assert_raise(SubcommandFailed) { importer.import(pkg_svn) }

        # Make a checkout fail
        FileUtils.rm_rf pkg_svn.srcdir
        assert_raise(SubcommandFailed) { importer.import(pkg_svn) }
    end

end
 
