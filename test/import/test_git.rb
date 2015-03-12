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
    
    describe "#initialize" do
        it "allows passing the branch as second argument for backward-compatibility way" do
            Autobuild.silent = true
            importer = Autobuild::Git.new('repo', 'branch', tag: 'test')
            assert_equal 'branch', importer.branch
        end
        it "raises ConfigException if the branch parameter and the branch options are both given" do
            Autobuild.silent = true
            assert_raises(Autobuild::ConfigException) do
                Autobuild::Git.new('repo', 'branch', branch: 'another')
            end
        end
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
                assert_equal( false, Autobuild::Git.at_least_version( 50,0,1 ) )
            end
        end
    end

    describe "#has_commit?" do
        before do
            importer.import(pkg)
        end

        it "returns true if the specified name resolves to a commit" do
            assert importer.has_commit?(pkg, importer.rev_parse(pkg, 'HEAD'))
        end
        it "returns true if the specified commit is present locally" do
            assert importer.has_commit?(pkg, importer.rev_parse(pkg, '8b09cb0febae222b31e2ee55f839c1e00dc7edc4'))
        end
        it "returns false if the specified name does not resolve to an object" do
            assert !importer.has_commit?(pkg, 'blabla')
        end
        it "returns false if the specified commit is not present locally" do
            assert !importer.has_commit?(pkg, 'c8cf0798b1d53931314a86bdb3e2ad874eb8deb5')
        end
        it "raises for any other error" do
            flexmock(Autobuild::Subprocess).should_receive(:run).
                and_raise(Autobuild::SubcommandFailed.new('test', 'test', 'bla', 200))
            assert_raises(Autobuild::SubcommandFailed) do
                importer.has_commit?(pkg, 'master')
            end
        end
    end

    describe "#has_branch?" do
        before do
            importer.import(pkg)
        end

        it "returns true if the branch exists" do
            assert importer.has_branch?(pkg, 'master')
        end

        it "returns false if the branch does not exist" do
            assert !importer.has_branch?(pkg, 'does_not_exist')
        end

        it "raises for any other error" do
            flexmock(Autobuild::Subprocess).should_receive(:run).
                and_raise(Autobuild::SubcommandFailed.new('test', 'test', 'bla', 200))
            assert_raises(Autobuild::SubcommandFailed) do
                importer.has_branch?(pkg, 'master')
            end
        end
    end

    describe "#detached_head?" do
        before do
            importer.import(pkg)
        end

        it "returns true if HEAD is detached" do
            importer.run_git(pkg, 'checkout', 'master~1')
            assert importer.detached_head?(pkg)
        end
        it "returns false if HEAD is pointing to a branch" do
            assert !importer.detached_head?(pkg)
        end
        it "raises for any other error" do
            flexmock(Autobuild::Subprocess).should_receive(:run).
                and_raise(Autobuild::SubcommandFailed.new('test', 'test', 'bla', 200))
            assert_raises(Autobuild::SubcommandFailed) do
                importer.detached_head?(pkg)
            end
        end
    end

    describe "#current_branch" do
        before do
            importer.import(pkg)
        end

        it "returns the current branch name" do
            importer.run_git(pkg, 'checkout', '-b', 'test')
            assert_equal 'refs/heads/test', importer.current_branch(pkg)
        end
        it "returns nil if the head is detached" do
            importer.run_git(pkg, 'checkout', 'master~1')
            assert importer.current_branch(pkg).nil?
        end
        it "raises for any other error" do
            flexmock(Autobuild::Subprocess).should_receive(:run).
                and_raise(Autobuild::SubcommandFailed.new('test', 'test', 'bla', 200))
            assert_raises(Autobuild::SubcommandFailed) do
                importer.current_branch(pkg)
            end
        end
    end

    describe "#rev_parse" do
        it "raises PackageException if the name does not exist" do
            importer.import(pkg)
            assert_raises(Autobuild::PackageException) do
                importer.rev_parse(pkg, 'does_not_exist')
            end
        end
    end

    describe "#show" do
        it "returns the content of a path at a commit" do
            importer.import(pkg)
            File.open(File.join(tempdir, 'git', 'test'), 'a') do |io|
                io.puts "newline"
            end
            head = importer.rev_parse(pkg, 'HEAD')
            importer.run_git(pkg, 'commit', '-a', '-m', 'test commit')
            assert_equal '', importer.show(pkg, head, 'test')
            assert_equal 'newline', importer.show(pkg, 'HEAD', 'test')
        end
    end

    describe ".has_uncommitted_changes?" do
        before do
            importer.import(pkg)
        end

        it "returns true if some files is modified" do
            File.open(File.join(tempdir, 'git', 'test'), 'a') do |io|
                io.puts "newline"
            end
            assert Autobuild::Git.has_uncommitted_changes?(pkg)
        end
        it "returns true if some files is modified and staged" do
            file = File.join(tempdir, 'git', 'test')
            File.open(file, 'a') { |io| io.puts "newline" }
            importer.run_git(pkg, 'add', file) 
            assert Autobuild::Git.has_uncommitted_changes?(pkg)
        end
        it "returns true if a new file is added" do
            newfile = File.join(tempdir, 'git', 'blabla')
            FileUtils.touch newfile
            importer.run_git(pkg, 'add', newfile) 
            assert Autobuild::Git.has_uncommitted_changes?(pkg)
        end
        it "returns true if a file has been removed" do
            FileUtils.rm_f File.join(tempdir, 'git', 'test')
            assert Autobuild::Git.has_uncommitted_changes?(pkg)
        end
        it "returns true if a file has been removed and staged" do
            delfile = File.join(tempdir, 'git', 'test')
            FileUtils.rm_f delfile
            importer.run_git(pkg, 'rm', delfile) 
            assert Autobuild::Git.has_uncommitted_changes?(pkg)
        end
    end

    describe "#commit_present_in?" do
        attr_reader :commits
        before do
            importer.import(pkg)
            @commits = [
                importer.rev_parse(pkg, 'HEAD'),
                importer.rev_parse(pkg, 'HEAD~1')]
        end

        it "returns true if the revision is in the provided branch" do
            assert importer.commit_present_in?(pkg, 'HEAD', 'master')
            assert importer.commit_present_in?(pkg, commits[0], 'master')
            assert importer.commit_present_in?(pkg, 'HEAD~1', 'master')
            assert importer.commit_present_in?(pkg, commits[1], 'master')
        end
        it "returns false if the revision is not in the provided branch" do
            importer.run_git(pkg, 'branch', 'fork', 'autobuild/fork')
            assert !importer.commit_present_in?(pkg, commits[0], "refs/heads/fork")
        end
        # git rev-parse return the tag ID for annotated tags instead of the
        # commit ID. This was in turn breaking commit_present_in?
        it "handles annotated tags properly" do
            importer.run_git(pkg, 'tag', '-a', '-m', 'tag0', "tag0", "HEAD~1")
            assert importer.commit_present_in?(pkg, 'tag0', 'master')
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
            it "creates the local branch at the specified commit if the branch does not exist" do
                importer.import(pkg)
                head = importer.rev_parse(pkg, 'HEAD')
                importer.local_branch = 'local'
                importer.import(pkg)
                assert_equal 'refs/heads/local', importer.current_branch(pkg)
                assert_equal head, importer.rev_parse(pkg, 'HEAD')
            end

            it "acts on local_branch" do
                importer.import(pkg)
                head = importer.rev_parse(pkg, 'HEAD')
                importer.run_git(pkg, 'reset', '--hard', 'master~1')
                importer.run_git(pkg, 'branch', 'local')
                importer.local_branch = 'local'
                importer.import(pkg)
                assert_equal 'refs/heads/local', importer.current_branch(pkg)
                assert_equal head, importer.rev_parse(pkg, 'refs/remotes/autobuild/master')
            end

            it "refuses to update if the local and remote branches have diverged" do
                importer.import(pkg)
                importer.run_git(pkg, 'reset', '--hard', 'master~1')
                File.open(File.join(tempdir, 'git', 'test'), 'a') do |io|
                    io.puts "test"
                end
                importer.run_git(pkg, 'commit', '-a', '-m', 'a fork commit')
                assert_raises(Autobuild::PackageException) do
                    importer.import(pkg)
                end
            end
            it "switches to the local branch regardless of the presence of the tag or commit" do
                importer.import(pkg)
                head = importer.rev_parse(pkg, 'HEAD')
                importer.run_git(pkg, 'reset', '--hard', 'master~1')
                importer.run_git(pkg, 'branch', 'local')
                importer.local_branch = 'local'
                importer.relocate(importer.repository, tag: 'third_commit')
                importer.update(pkg)
                assert_equal 'refs/heads/local', importer.current_branch(pkg)
                assert_equal head, importer.rev_parse(pkg, 'refs/remotes/autobuild/master')
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

            def pin_importer(id, options = Hash.new)
                importer.relocate(importer.repository, options.merge(commit: commits[id]))
            end

            it "fetches from the remote repository if the commit is not present locally" do
                untar('gitrepo-with-extra-commit-and-tag.tar')
                importer.import(pkg)
                extra_repo = File.join(tempdir, 'gitrepo-with-extra-commit-and-tag.git')
                importer.relocate(extra_repo, commit: '1ddb20665622279700770be09f9a291b37c9b631')
                importer.import(pkg, reset: false)
                assert_equal  '1ddb20665622279700770be09f9a291b37c9b631', importer.rev_parse(pkg, 'HEAD')
            end

            common_commit_and_tag_behaviour
        end
        describe "with a specific tag given" do
            attr_reader :commits

            before do
                importer = Autobuild.git(gitrepo)
                pkg = Autobuild::Package.new 'commits'
                pkg.srcdir = gitrepo
                pkg.importer = importer
                importer.run_git_bare(pkg, 'tag', "tag0", "HEAD")
                importer.run_git_bare(pkg, 'tag', "tag1", "HEAD~1")
                @commits = [
                    importer.rev_parse(pkg, 'HEAD'),
                    importer.rev_parse(pkg, 'HEAD~1')]
            end

            def assert_on_commit(id)
                assert_equal commits[id], importer.rev_parse(pkg, 'HEAD')
            end

            def pin_importer(id, options = Hash.new)
                importer.relocate(importer.repository, options.merge(tag: "tag#{id}"))
            end

            it "fetches from the remote repository if the commit is not present locally" do
                untar('gitrepo-with-extra-commit-and-tag.tar')
                importer.import(pkg)
                extra_repo = File.join(tempdir, 'gitrepo-with-extra-commit-and-tag.git')
                importer.relocate(extra_repo, tag: 'third_commit')
                importer.import(pkg, reset: false)
                tag_id = importer.rev_parse(pkg, 'third_commit')
                assert_equal tag_id, importer.rev_parse(pkg, 'HEAD')
            end

            common_commit_and_tag_behaviour
        end
    end
end

