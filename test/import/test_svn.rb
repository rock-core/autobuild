require 'autobuild/test'

describe Autobuild::SVN do
    attr_reader :svnrepo, :svnroot, :pkg_svn

    before do
        untar('svnroot.tar')
        @svnrepo = File.join(tempdir, 'svnroot')
        @svnroot = "file://#{svnrepo}/svn"
        @pkg_svn = Autobuild::Package.new 'svn'
        pkg_svn.srcdir = File.join(tempdir, 'svn')
    end

    describe "checkout" do
        it "checks out the repository if the working copy does not exist" do
            importer = Autobuild.svn(svnroot)
            importer.import(pkg_svn)
            assert File.exist?(File.join(pkg_svn.srcdir, 'test'))
        end

        it "fails if the repository does not exist" do
            importer = Autobuild.svn("file:///does/not/exist")
            assert_raises(Autobuild::SubcommandFailed) { importer.import(pkg_svn) }
        end

        it "checks out a specific revision" do
            importer = Autobuild.svn(svnroot, revision: 1)
            importer.import(pkg_svn)
            assert_equal 1, importer.svn_revision(pkg_svn)
        end
    end

    describe "update" do
        it "fails with SubcommandFailed if the repository does not exist" do
            importer = Autobuild.svn(svnroot)
            importer.import(pkg_svn)
            FileUtils.rm_rf svnrepo
            assert_raises(Autobuild::SubcommandFailed) { importer.import(pkg_svn) }
        end

        it "fails if the working copy is not a svn working copy" do
            importer = Autobuild.svn(svnroot)
            FileUtils.mkdir_p pkg_svn.srcdir
            assert_raises(Autobuild::SubcommandFailed) { importer.import(pkg_svn) }
        end

        it "updates the working copy" do
            importer = Autobuild.svn(svnroot, revision: 1)
            importer.import(pkg_svn)
            importer.relocate(importer.svnroot, revision: nil)
            importer.import(pkg_svn)
            assert_equal 3, importer.svn_revision(pkg_svn)
        end

        it "updates if the target revision is not present even if reset is false" do
            importer = Autobuild.svn(svnroot, revision: 1)
            importer.import(pkg_svn)
            importer.relocate(importer.svnroot, revision: 2)
            importer.import(pkg_svn, reset: false)
            assert_equal 2, importer.svn_revision(pkg_svn)
        end

        it "does nothing if the target revision is present and reset is false" do
            importer = Autobuild.svn(svnroot, revision: 2)
            importer.import(pkg_svn)
            importer.relocate(importer.svnroot, revision: 1)
            importer.import(pkg_svn, reset: false)
            assert_equal 2, importer.svn_revision(pkg_svn)
        end

        it "resets to the specified revision if reset is true" do
            importer = Autobuild.svn(svnroot, revision: 2)
            importer.import(pkg_svn)
            importer.relocate(importer.svnroot, revision: 1)
            importer.import(pkg_svn, reset: true)
            assert_equal 1, importer.svn_revision(pkg_svn)
        end

        it "fails if the svnroot is not the same than the WC's svnroot" do
            importer = Autobuild.svn(svnroot, revision: 1)
            importer.import(pkg_svn)
            FileUtils.mv svnrepo, "#{svnrepo}.2"
            importer = Autobuild.svn("file://#{svnrepo}.2/svn")
            assert_raises(Autobuild::ConfigException) { importer.import(pkg_svn) }
        end
    end

    describe "svn_revision" do
        it "returns the current checkout revision" do
            importer = Autobuild.svn(svnroot, revision: 2)
            importer.import(pkg_svn)
            assert_equal 2, importer.svn_revision(pkg_svn)
        end
    end

    describe "status" do
        it "lists the log entries that are on the remote but not locally" do
            importer = Autobuild.svn(svnroot, revision: 1)
            importer.import(pkg_svn)
            importer.relocate(importer.svnroot, revision: nil)
            status = importer.status(pkg_svn)
            assert_equal 2, status.remote_commits.size
            assert(/second revision/ === status.remote_commits[0], status.remote_commits[0])
        end

        it "indicates if there are no local modifications" do
            importer = Autobuild.svn(svnroot, revision: 1)
            importer.import(pkg_svn)
            refute importer.status(pkg_svn).uncommitted_code
        end

        it "indicates if there are modified files" do
            importer = Autobuild.svn(svnroot)
            importer.import(pkg_svn)
            File.open(File.join(pkg_svn.srcdir, "test"), 'a') do |io|
                io.puts "newline"
            end
            assert importer.status(pkg_svn).uncommitted_code
        end

        it "indicates if there are added files" do
            importer = Autobuild.svn(svnroot)
            importer.import(pkg_svn)
            FileUtils.touch File.join(pkg_svn.srcdir, "test3")
            importer.run_svn(pkg_svn, "add", "test3")
            assert importer.status(pkg_svn).uncommitted_code
        end

        it "indicates if there are removed files" do
            importer = Autobuild.svn(svnroot)
            importer.import(pkg_svn)
            importer.run_svn(pkg_svn, "rm", "test")
            assert importer.status(pkg_svn).uncommitted_code
        end

        it "indicates if there are moved files" do
            importer = Autobuild.svn(svnroot)
            importer.import(pkg_svn)
            importer.run_svn(pkg_svn, "mv", "test", 'test3')
            assert importer.status(pkg_svn).uncommitted_code
        end
    end

    describe "fingerprint generation" do
        before do
            current_revision = '2'
            @importer = Autobuild.svn(svnroot, revision: current_revision)
            expected_source_string = "Revision: "+current_revision+"\nURL: "+svnroot
            @expected_vcs_fingerprint = Digest::SHA1.hexdigest(expected_source_string)
            @importer.import(pkg_svn)
        end
        it "returns the expected value" do
            assert_equal @expected_vcs_fingerprint, @importer.fingerprint(pkg_svn)
        end
        it "computes also the patches' fingerprint" do
            test_patches = [['/path/to/patch', 1, 'source_test'],['other/path', 2, 'source2_test']]
            # we expect paths will be ignored and the patches array to be
            # flatenned into a string
            expected_patch_fingerprint = Digest::SHA1.hexdigest('1source_test2source2_test')
            flexmock(@importer).
                should_receive(:currently_applied_patches).
                and_return(test_patches)
            flexmock(@importer).
                should_receive(:patches).
                and_return(test_patches)

            expected_fingerprint = Digest::SHA1.hexdigest(@expected_vcs_fingerprint +
                expected_patch_fingerprint)

            assert_equal expected_fingerprint, @importer.fingerprint(pkg_svn)
        end
    end

end
