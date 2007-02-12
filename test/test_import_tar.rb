$LOAD_PATH.unshift File.expand_path('..', File.dirname(__FILE__))
$LOAD_PATH << File.expand_path('../lib', File.dirname(__FILE__))
require 'test/unit'
require 'test/tools'
require 'autobuild/import/cvs'
require 'autobuild/import/svn'
require 'autobuild/import/tar'
require 'webrick'

include Autobuild

class TC_TarImporter < Test::Unit::TestCase
    include WEBrick
    Package = Struct.new :srcdir, :name

    def setup
        Autobuild.logdir = "#{TestTools.tempdir}/log"
        FileUtils.mkdir_p(Autobuild.logdir)

        @datadir = File.join(TestTools.tempdir, 'data')
        FileUtils.mkdir_p(@datadir)
        @tarfile = File.join(@datadir, 'tarimport.tar.gz')
        FileUtils.cp(File.join(TestTools::DATADIR, 'tarimport.tar.gz'), @tarfile)
        
        @cachedir = File.join(TestTools.tempdir, 'cache')
    end
    
    def teardown
        TestTools.clean
    end

    def test_tar_mode
        assert_equal(TarImporter::Plain, TarImporter.url_to_mode('tarfile.tar'))
        assert_equal(TarImporter::Gzip, TarImporter.url_to_mode('tarfile.tar.gz'))
        assert_equal(TarImporter::Bzip, TarImporter.url_to_mode('tarfile.tar.bz2'))
    end

    def test_tar_valid_url
        assert_raise(ConfigException) {
            TarImporter.new 'ccc://localhost/files/tarimport.tar.gz', :cachedir => @cachedir
        }
    end

    def web_server
        s = HTTPServer.new :Port => 2000, :DocumentRoot => TestTools.tempdir
        s.mount("/files", HTTPServlet::FileHandler, TestTools.tempdir)
        webrick = Thread.new { s.start }

        yield

    ensure
        s.shutdown
        webrick.join
    end

    def test_tar_remote
        web_server do
            # Try to get the file through the http server
            pkg = Package.new File.join(TestTools.tempdir, 'tarimport'), 'tarimport'
            importer = TarImporter.new 'http://localhost:2000/files/data/tarimport.tar.gz', :cachedir => @cachedir

            importer.checkout(pkg)
            assert(File.directory?(pkg.srcdir))
            assert(!importer.update_cache)

            sleep 2 # The Time class have a 1-second resolution
            FileUtils.touch @tarfile
            assert(importer.update_cache)
            assert(!importer.update_cache)
        end
    end

    def test_tar_remote_notfound
        web_server do
            # Try to get the file through the http server
            pkg = Package.new File.join(TestTools.tempdir, 'tarimport'), 'tarimport'
            importer = TarImporter.new 'http://localhost:2000/files/data/tarimport-nofile.tar.gz', :cachedir => @cachedir

            assert_raise(Autobuild::Exception) { importer.checkout(pkg) }
        end
    end
end
 
