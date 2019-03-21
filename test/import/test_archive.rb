require 'autobuild/test'
require 'webrick'

module Autobuild
    describe ArchiveImporter do
        before do
            Autobuild.logdir = "#{tempdir}/log"
            FileUtils.mkdir_p(Autobuild.logdir)

            @datadir = File.join(tempdir, 'data')
            FileUtils.mkdir_p(@datadir)
            @tarfile = File.join(@datadir, 'tarimport.tar.gz')
            FileUtils.cp(File.join(data_dir, 'tarimport.tar.gz'), @tarfile)

            @cachedir = File.join(tempdir, 'cache')
            @wrong_expected_digest = Digest::SHA1.hexdigest 'test'
            # expected from the local test file used
            @correct_expected_digest = 'aa06e469fdfbeb3b3a556be0b45a0554feaf9226'
        end

        describe "http downloads" do
            before do
                @pkg = Package.new 'tarimport'
                @pkg.srcdir = File.join(tempdir, 'tarimport')
                @importer = ArchiveImporter.new 'http://localhost:2000/redirect',
                    cachedir: @cachedir
            end

            it "does nothing if the server returns NotModified" do
                web_server { @importer.checkout(@pkg) }
                web_server(redirect_code: 304) do
                    refute @importer.update_cache(@pkg)
                end
            end
            it "updates if the remote file is newer than the local file and "\
                "update_cached_file is true" do
                @importer.update_cached_file = true
                web_server { @importer.checkout(@pkg) }
                FileUtils.touch @tarfile, mtime: (Time.now + 2)
                web_server do
                    assert @importer.update_cache(@pkg)
                end
            end
            it "does not update if update_cached_file is false, even if the remote "\
                "file is newer" do
                @importer.update_cached_file = false
                web_server { @importer.checkout(@pkg) }
                FileUtils.touch @tarfile, mtime: (Time.now + 2)
                web_server do
                    refute @importer.update_cache(@pkg)
                end
            end
            it "handles redirections to a full URI" do
                [302, 303, 307, 301, 308].each do |code|
                    location = "http://localhost:2000/files/data/tarimport.tar.gz"
                    web_server(redirect_code: code, redirect_to: location) do
                        @importer.checkout(@pkg)
                    end
                end
            end
            it "handles redirections to a path" do
                [302, 303, 307, 301, 308].each do |code|
                    web_server(redirect_code: code) do
                        @importer.checkout(@pkg)
                    end
                end
            end
        end

        describe "update" do
            before do
                @pkg = Package.new 'tarimport'
                @pkg.srcdir = File.join(tempdir, 'tarimport')
                @importer = ArchiveImporter.new \
                    'http://localhost:2000//files/data/tarimport.tar.gz',
                    cachedir: @cachedir
            end

            describe "when the remote file changed" do
                before do
                    start_web_server
                    @importer.checkout(@pkg)
                    File.open File.join(@importer.checkout_digest_stamp(@pkg)), 'w' do
                    end
                    flexmock(TTY::Prompt)
                end
                after do
                    ArchiveImporter.auto_update = false
                    stop_web_server
                end
                it "asks the user about deleting the folder if the archive digest changed" do
                    TTY::Prompt.new_instances.should_receive(:ask).once.and_return(true)
                    assert @importer.update(@pkg, allow_interactive: true)
                end
                it "raises if the folder needs to be deleted but allow_interactive is false" do
                    TTY::Prompt.new_instances.should_receive(:ask).never
                    assert_raises(Autobuild::InteractionRequired) do
                        @importer.update(@pkg, allow_interactive: false)
                    end
                end
                it "deletes the folder without asking if auto_update? is set" do
                    ArchiveImporter.auto_update = true
                    TTY::Prompt.new_instances.should_receive(:ask).never
                    assert @importer.update(@pkg, allow_interactive: false)
                end
            end
        end

        describe "wrong digest" do
            before do
                @pkg = Package.new 'tarimport'
                @pkg.srcdir = File.join(tempdir, 'tarimport')
                @importer = ArchiveImporter.new \
                    'http://localhost:2000//files/data/tarimport.tar.gz',
                    cachedir: @cachedir,
                    expected_digest: @wrong_expected_digest
            end

            describe "when setting a wrong expected digest" do
                before do
                    start_web_server
                end
                after do
                    stop_web_server
                end
                it "raises exception" do
                    assert_raises(Autobuild::ConfigException) do
                        @importer.checkout(@pkg)
                    end
                end
            end
        end

        describe "correct digest" do
            before do
                @pkg = Package.new 'tarimport'
                @pkg.srcdir = File.join(tempdir, 'tarimport')
                @importer = ArchiveImporter.new \
                    'http://localhost:2000//files/data/tarimport.tar.gz',
                    cachedir: @cachedir,
                    expected_digest: @correct_expected_digest
            end

            describe "when setting an expected digest" do
                before do
                    start_web_server
                end
                after do
                    stop_web_server
                end
                it "checkout is done normally" do
                    assert @importer.checkout(@pkg)
                end
            end
            describe "fingerprint generation" do
                before do
                    @expected_vcs_fingerprint = @correct_expected_digest
                    start_web_server
                end
                after do
                    stop_web_server
                end
                it "returns the expected value" do
                    @importer.import(@pkg)
                    assert_equal @expected_vcs_fingerprint, @importer.fingerprint(@pkg)
                end
                it "computes also the patches' fingerprint" do
                    test_patches = [['/path/to/patch', 1, 'source_test'],['other/path', 2, 'source2_test']]
                    # we expect paths will be ignored and the patches array to be
                    # flattened into a string
                    expected_patch_fingerprint = Digest::SHA1.hexdigest('1source_test2source2_test')

                    @importer.import(@pkg)

                    flexmock(@importer).
                        should_receive(:currently_applied_patches).
                        and_return(test_patches)
                    flexmock(@importer).
                        should_receive(:patches).
                        and_return(test_patches)
                    # archive applies and unapplies patches, we are not testing 
                    # this so we will mock it
                    flexmock(@importer).
                        should_receive(:call_patch).
                        and_return(true)

                    expected_fingerprint = Digest::SHA1.hexdigest(@expected_vcs_fingerprint + 
                        expected_patch_fingerprint)
        
                    assert_equal expected_fingerprint, @importer.fingerprint(@pkg)
                end
            end
        end

        def start_web_server(redirect_code: 301, redirect_to: '/files/data/tarimport.tar.gz')
            s = WEBrick::HTTPServer.new :Port => 2000, :DocumentRoot => tempdir
            s.mount_proc "/redirect" do |_req, res|
                res.status = redirect_code
                res.header['location'] = redirect_to
            end
            s.mount("/files", WEBrick::HTTPServlet::FileHandler, tempdir)

            @webrick_server = s
            @webrick_thread = Thread.new { s.start }

            loop do
                response = nil
                Net::HTTP.start('localhost', 2000) do |http|
                    response = http.head '/files/data/tarimport.tar.gz'
                end
                break if Net::HTTPOK === response
            end
        end

        def stop_web_server
            @webrick_server&.shutdown
            @webrick_thread&.join
        end

        def web_server(redirect_code: 301, redirect_to: '/files/data/tarimport.tar.gz')
            start_web_server(redirect_code: redirect_code, redirect_to: redirect_to)
            yield
        ensure
            stop_web_server
        end
    end
end

class TestTarImporter < Minitest::Test
    include Autobuild
    include WEBrick

    def setup
        super

        Autobuild.logdir = "#{tempdir}/log"
        FileUtils.mkdir_p(Autobuild.logdir)

        @datadir = File.join(tempdir, 'data')
        FileUtils.mkdir_p(@datadir)
        @tarfile = File.join(@datadir, 'tarimport.tar.gz')
        FileUtils.cp(File.join(data_dir, 'tarimport.tar.gz'), @tarfile)

        @cachedir = File.join(tempdir, 'cache')
    end

    def test_tar_mode
        assert_equal(TarImporter::Plain, TarImporter.filename_to_mode('tarfile.tar'))
        assert_equal(TarImporter::Gzip, TarImporter.filename_to_mode('tarfile.tar.gz'))
        assert_equal(TarImporter::Bzip, TarImporter.filename_to_mode('tarfile.tar.bz2'))
    end

    def test_it_sets_the_repository_id_to_the_normalized_url
        importer = TarImporter.new "FILE://test/file"
        assert_equal "file://test/file", importer.repository_id.to_str
    end

    def test_it_sets_the_source_id_to_the_normalized_url
        importer = TarImporter.new "FILE://test/file"
        assert_equal "file://test/file", importer.source_id.to_str
    end

    def test_it_does_not_delete_a_locally_specified_archive_on_error
        dummy_tar = File.join(@datadir, "dummy.tar")
        FileUtils.touch dummy_tar
        importer = TarImporter.new "file://#{dummy_tar}"
        pkg = Package.new 'tarimport'
        assert_raises(Autobuild::SubcommandFailed) { importer.checkout(pkg) }
        assert File.file?(dummy_tar)
    end

    def test_tar_valid_url
        assert_raises(ConfigException) do
            TarImporter.new 'ccc://localhost/files/tarimport.tar.gz', :cachedir => @cachedir
        end
    end

    def web_server
        s = HTTPServer.new :Port => 2000, :DocumentRoot => tempdir
        s.mount("/files", HTTPServlet::FileHandler, tempdir)
        t = Thread.new { s.start }

        yield
    ensure
        if s
            s.shutdown
            t.join
        end
    end

    def test_tar_remote
        web_server do
            # Try to get the file through the http server
            pkg = Package.new 'tarimport'
            pkg.srcdir = File.join(tempdir, 'tarimport')
            importer = TarImporter.new 'http://localhost:2000/files/data/tarimport.tar.gz',
                cachedir: @cachedir,
                update_cached_file: true

            importer.checkout(pkg)
            assert(File.directory?(pkg.srcdir))
            assert(!importer.update_cache(pkg))

            sleep 2 # The Time class have a 1-second resolution
            FileUtils.touch @tarfile
            assert(importer.update_cache(pkg))
            assert(!importer.update_cache(pkg))
        end
    end

    def test_tar_remote_notfound
        web_server do
            # Try to get the file through the http server
            pkg = Package.new 'tarimport'
            pkg.srcdir = File.join(tempdir, 'tarimport')
            importer = TarImporter.new 'http://localhost:2000/files/data/tarimport-nofile.tar.gz', :cachedir => @cachedir

            e = assert_raises(Autobuild::PackageException) { importer.checkout(pkg) }
            assert_equal pkg, e.target
            assert_equal 'import', e.phase
            assert_match(/NotFound/, e.message)
        end
    end
end
