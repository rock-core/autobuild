require 'autobuild/test'

describe Autobuild::Git do
    attr_reader :pkg, :importer, :gitrepo
    before do
        untar('gitrepo.tar')
        @gitrepo = File.join(tempdir, 'gitrepo.git')
        @pkg = Autobuild::Package.new 'test'
        pkg.srcdir = File.join(tempdir, 'git')
        @importer = Autobuild.git(gitrepo)
        pkg.importer = importer
    end

    describe "version_compare" do
        it "should return -1 if the actual version is greater" do
            assert_equal(-1, Autobuild::Git.compare_versions([2, 1, 0], [2, 0, 1]))
        end
        it "should return 0 if the versions are equal" do
            assert_equal(0, Autobuild::Git.compare_versions([2, 1, 0], [2, 1, 0]))
        end
        it "should return 1 if the required version is greater" do
            assert_equal(1, Autobuild::Git.compare_versions([2, 0, 1], [2, 1, 0]))
            assert_equal(1, Autobuild::Git.compare_versions([1, 9, 1], [2, 1, 0]))
        end
        it "should fill missing version parts with zeros" do
            assert_equal(-1, Autobuild::Git.compare_versions([2, 1], [2, 0, 1]))
            assert_equal(-1, Autobuild::Git.compare_versions([2, 1, 0], [2, 0]))
            assert_equal(0, Autobuild::Git.compare_versions([2, 1], [2, 1, 0]))
            assert_equal(0, Autobuild::Git.compare_versions([2, 1, 0], [2, 1]))
            assert_equal(1, Autobuild::Git.compare_versions([2, 1], [2, 1, 1]))
            assert_equal(1, Autobuild::Git.compare_versions([2, 1, 1], [2, 2]))
        end
    end
    describe "at_least_version" do
        Autobuild::Git.stub :version, [1,9,1] do
            it "should be true if required version is smaller" do
                assert_equal( true, Autobuild::Git.at_least_version( 1,8,1 ) ) 
            end
            it "should be false if required version is greater" do
                assert_equal( false, Autobuild::Git.at_least_version( 2,0,1 ) )
            end
        end
    end

    describe "#has_commit?" do
        before do
            importer.import(pkg)
        end

        it "returns true if the specified commit is present locally" do
            assert importer.has_commit?(pkg, importer.rev_parse(pkg, 'HEAD'))
        end
        it "returns false if the specified commit is not present locally" do
            assert !importer.has_commit?(pkg, 'blabla')
        end
    end

    describe "update" do
        def self.common_commit_and_tag_behaviour

            it "does not access the repository if the target is already merged and reset is false" do
                importer.import(pkg)

                # We relocate to a non-existing repository to ensure that it
                # does not try to access it
                importer.relocate('/does/not/exist')
                pin_importer(1)
                importer.import(pkg, reset: false)
                assert_on_commit 0
            end
            it "does not access the repository if the target is already HEAD and reset is true" do
                importer.import(pkg)
                pin_importer(0)
                importer.relocate('/does/not/exist')
                importer.import(pkg, reset: true)
                assert_on_commit 0
            end
            it "does not access the remote repository if the commit is present locally" do
                pin_importer(1)
                importer.import(pkg)
                pin_importer(0)
                importer.relocate('/does/not/exist')
                importer.import(pkg, reset: false)
                assert_on_commit 0
            end
            it "attempts to merge the target commit if it is not present in HEAD" do
                pin_importer(1)
                importer.import(pkg)
                pin_importer(0)
                importer.import(pkg, reset: false)
                assert_on_commit 0
            end
            it "resets if reset is true" do
                importer.import(pkg)
                pin_importer(1)
                importer.import(pkg, reset: true)
                assert_on_commit 1
            end
            it "refuses to reset if some commits are present locally but not in the remote branch" do
                importer.import(pkg)
                File.open(File.join(tempdir, 'git', 'test3'), 'w') do |io|
                    io.puts "test"
                end
                importer.run_git(pkg, 'add', 'test3')
                importer.run_git(pkg, 'commit', '-a', '-m', 'third commit')
                current_head = importer.rev_parse(pkg, 'HEAD')
                pin_importer(1)
                assert_raises(Autobuild::ImporterCannotReset) do
                    importer.import(pkg, reset: true)
                end
                assert_equal current_head, importer.rev_parse(pkg, 'HEAD')
            end
        end
        describe "with a specific commit given" do
            def assert_on_commit(id)
                assert_equal commits[id], importer.rev_parse(pkg, 'HEAD')
            end
            def commits
                if !@commits
                    importer = Autobuild.git(gitrepo)
                    pkg = Autobuild::Package.new 'commits'
                    pkg.srcdir = gitrepo
                    pkg.importer = importer
                    @commits = [
                        importer.rev_parse(pkg, 'HEAD'),
                        importer.rev_parse(pkg, 'HEAD~1')]
                end
                @commits
            end

            def pin_importer(id)
                importer.relocate(importer.repository, commit: commits[id])
            end

            common_commit_and_tag_behaviour
        end
        describe "with a specific tag given" do
        end
    end
end
