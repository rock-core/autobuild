$LOAD_PATH << File.expand_path('../lib', File.dirname(__FILE__))
$LOAD_PATH << File.dirname(__FILE__)
require 'test/unit'
require 'conffile-generator'
require 'autobuild/import/cvs'
require 'autobuild/import/svn'

class TC_Import < Test::Unit::TestCase
    Package = Struct.new :srcdir, :target

    def setup
        $PROGRAMS = {}
        $LOGDIR = "#{ConffileGenerator.tempdir}/log"
        FileUtils.mkdir_p($LOGDIR)

        @cvsroot = File.join(DATADIR, 'cvsroot')
        @pkg_cvs = Package.new File.join(ConffileGenerator.tempdir, 'cvs'), :cvs

        @svnroot = "file:///#{File.join(DATADIR, 'svnroot')}"
        @pkg_svn = Package.new File.join(ConffileGenerator.tempdir, 'svn'), :svn
    end
    
    def teardown
        $PROGRAMS = nil
        ConffileGenerator.clean
    end

    def test_cvs
        importer = Import.cvs [ @cvsroot, 'cvs' ], {}
        importer.import(@pkg_cvs)
    end

    def test_svn
        importer = Import.svn [ @svnroot, 'svn' ], {}
        importer.import(@pkg_svn)

        FileUtils.rm_rf importer.import(@pkg_svn.srcdir)
        importer = Import.svn File.join(@svnroot, 'svn'), {}
        importer.import(@pkg_svn)
    end
end
 
