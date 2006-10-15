$LOAD_PATH.unshift File.expand_path('..', File.dirname(__FILE__))
$LOAD_PATH << File.expand_path('../lib', File.dirname(__FILE__))
require 'test/unit'
require 'test/tools'
require 'autobuild/import/svn'

class TC_SVNImport < Test::Unit::TestCase
    include Autobuild
    Package = Struct.new :srcdir, :name

    def setup
        Autobuild.logdir = "#{TestTools.tempdir}/log"
        FileUtils.mkdir_p(Autobuild.logdir)
    end
    
    def teardown
        TestTools.clean
    end

    def test_svn
        TestTools.untar('svnroot.tar')
        svnrepo = File.join(TestTools.tempdir, 'svnroot')
        svnroot = "file://#{svnrepo}/svn"
        pkg_svn = Package.new File.join(TestTools.tempdir, 'svn'), :svn

        # Make a checkout with a splitted URL
        importer = Autobuild.svn(svnroot)
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
 
