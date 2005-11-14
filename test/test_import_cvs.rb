$LOAD_PATH.unshift File.expand_path('..', File.dirname(__FILE__))
$LOAD_PATH << File.expand_path('../lib', File.dirname(__FILE__))
require 'test/unit'
require 'test/tools'
require 'autobuild/import/cvs'
require 'autobuild/import/svn'
require 'autobuild/import/tar'

include Autobuild

class TC_CVSImport < Test::Unit::TestCase
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
        assert_raise(Autobuild::SubcommandFailed) { importer.import pkg_cvs }

        # Make a checkout fail
        FileUtils.rm_rf pkg_cvs.srcdir
        assert_raise(Autobuild::SubcommandFailed) { importer.import pkg_cvs }
    end
end


