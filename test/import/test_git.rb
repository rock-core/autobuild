require 'autobuild/test'

describe Autobuild::Git do
    attr_reader :pkg, :importer, :gitrepo
    before do
        tempdir = untar('gitrepo.tar')
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
        it "takes a local_branch argument" do
            git = Autobuild::Git.new('repo', local_branch: 'test')
            assert_equal "test", git.local_branch
            assert_equal nil, git.remote_branch
        end
        it "takes a remote_branch argument" do
            git = Autobuild::Git.new('repo', remote_branch: 'test')
            assert_equal nil, git.local_branch
            assert_equal "test", git.remote_branch
        end
        it 'picks the default alternates by default' do
            flexmock(Autobuild::Git, default_alternates: (alt = [flexmock]))
            git = Autobuild::Git.new('repo')
            assert_equal alt, git.alternates
        end
        it 'does not pick the default alternates if the importer is set up to use submodules' do
            flexmock(Autobuild::Git, default_alternates: (alt = [flexmock]))
            git = Autobuild::Git.new('repo', with_submodules: true)
            assert_equal [], git.alternates
        end
    end

    describe "#relocate" do
        it "reuses the branch if not given as option" do
            importer.branch = 'random'
            importer.relocate('test')
            assert_equal 'random', importer.local_branch
            assert_equal 'random', importer.remote_branch
        end
        it "overrides the branch by the given option" do
            importer.branch = 'random'
            importer.relocate('test', branch: 'test')
            assert_equal 'test', importer.local_branch
            assert_equal 'test', importer.remote_branch
        end
        it "overrides the local branch by the given option" do
            importer.branch = 'random'
            importer.relocate('test', local_branch: 'test')
            assert_equal 'test', importer.local_branch
            assert_equal 'random', importer.remote_branch
        end
        it "overrides the remote branch by the given option" do
            importer.branch = 'random'
            importer.relocate('test', remote_branch: 'test')
            assert_equal 'random', importer.local_branch
            assert_equal 'test', importer.remote_branch
        end
        it "reuses the local branch if not given as option" do
            importer.local_branch = 'random'
            importer.relocate('test')
            assert_equal 'random', importer.local_branch
        end
        it "reuses the remote branch if not given as option" do
            importer.remote_branch = 'random'
            importer.relocate('test')
            assert_equal 'random', importer.remote_branch
        end
        it "raises if attempting to use a full ref as local branch" do
            assert_raises(ArgumentError) do
                importer.relocate("test", local_branch: "refs/heads/master")
            end
        end
        it "raises if attempting to use a full ref as branch" do
            assert_raises(ArgumentError) do
                importer.relocate("test", local_branch: "refs/heads/master")
            end
        end
        it "accepts a full ref as remote branch" do
            importer.relocate("test", remote_branch: "refs/heads/master")
            assert_equal nil, importer.local_branch
            assert_equal "refs/heads/master", importer.remote_branch
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
        Autobuild::Git.stub :version, [1, 9, 1] do
            it "should be true if required version is smaller" do
                assert_equal(true, Autobuild::Git.at_least_version(1, 8, 1))
            end
            it "should be false if required version is greater" do
                assert_equal(false, Autobuild::Git.at_least_version(50, 0, 1))
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

    describe "#checkout" do
        before do
            @importer =
                Autobuild.git(gitrepo, remote_branch: 'refs/heads/master')

            pkg.importer = importer
            importer.import(pkg)
        end
        it "raises if a full ref is provided while cloning a single branch" do
            importer = Autobuild::Git.new(
                'repo',
                remote_branch: 'refs/heads/test',
                single_branch: true
            )

            assert_raises(ArgumentError) do
                importer.checkout(pkg)
            end
        end
        it "does not raise on checkout if remote branch lacks commits" do
            flexmock(Autobuild::Subprocess)
                .should_receive(:run)
                .with(
                    any, :import, 'git', 'clone', '-o', 'autobuild',
                    File.join(tempdir, 'gitrepo.git'),
                    File.join(tempdir, 'git'), any
                )

            flexmock(Autobuild::Subprocess).should_receive(:run).pass_thru

            importer.run_git(pkg, 'checkout', '-b', 'test')
            File.open(File.join(tempdir, 'git', 'test'), 'a') do |io|
                io.puts "newline"
            end

            importer.run_git(pkg, 'commit', '-a', '-m', 'test commit')
            importer.local_branch = 'test'
            importer.checkout(pkg)
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
                importer.rev_parse(pkg, 'HEAD~1')
            ]
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

    describe "#tags" do
        before do
            importer.import(pkg)
        end

        it "lists the tags from the repository and returns their name and commit" do
            assert_equal Hash["third_commit" => "1ddb20665622279700770be09f9a291b37c9b631"],
                importer.tags(pkg)
        end
        it "fetches new tags by default" do
            system "git", "tag", "test", chdir: @gitrepo
            assert_equal Set["third_commit", 'test'],
                importer.tags(pkg).keys.to_set
        end
        it "does not fetch new tags if only_local: true is given" do
            system "git", "tag", "test", chdir: @gitrepo
            assert_equal ["third_commit"],
                importer.tags(pkg, only_local: true).keys
        end
    end

    describe "update" do
        it "accepts a full ref as remote_branch" do
            importer.relocate(importer.repository,
                local_branch: 'test', remote_branch: 'refs/heads/master')
            importer.import(pkg)
            assert_equal 'refs/heads/test', importer.current_branch(pkg)
        end

        def self.common_commit_and_tag_behaviour
            it "does not access the repository if the target is already merged and reset is false" do
                importer.import(pkg)

                # We relocate to a non-existing repository to ensure that it
                # does not try to access it
                importer.relocate('/does/not/exist')
                pin_importer('tip~1')
                assert_equal false, importer.import(pkg, reset: false)
                assert_on_commit "tip"
            end
            it "does not access the repository if the target is already HEAD and reset is true" do
                importer.import(pkg)
                pin_importer('tip')
                importer.relocate('/does/not/exist')
                assert_equal false, importer.import(pkg, reset: true)
                assert_on_commit "tip"
            end
            it "does not access the remote repository if the commit is present locally" do
                pin_importer('tip~1')
                importer.import(pkg)
                pin_importer('tip')
                importer.relocate('/does/not/exist')
                assert importer.import(pkg, reset: false)
                assert_on_commit "tip"
            end
            it "attempts to merge the target commit if it is not present in HEAD" do
                pin_importer('tip~1')
                importer.import(pkg)
                pin_importer('tip')
                assert importer.import(pkg, reset: false)
                assert_on_commit "tip"
            end
            it "resets if reset is true" do
                importer.import(pkg)
                pin_importer('tip~1')
                assert importer.import(pkg, reset: true)
                assert_on_commit "tip~1"
            end
            it "refuses to reset if some commits are present locally but not in the remote branch" do
                importer.import(pkg)
                File.open(File.join(tempdir, 'git', 'test3'), 'w') do |io|
                    io.puts "test"
                end
                importer.run_git(pkg, 'add', 'test3')
                importer.run_git(pkg, 'commit', '-a', '-m', 'third commit')
                current_head = importer.rev_parse(pkg, 'HEAD')
                pin_importer('tip~1')
                assert_raises(Autobuild::ImporterCannotReset) do
                    importer.import(pkg, reset: true)
                end
                assert_equal current_head, importer.rev_parse(pkg, 'HEAD')
            end
            it "creates the local branch at the specified commit if the branch does not exist" do
                importer.import(pkg)
                head = importer.rev_parse(pkg, 'HEAD')
                importer.local_branch = 'local'
                assert importer.import(pkg)
                assert_equal 'refs/heads/local', importer.current_branch(pkg)
                assert_equal head, importer.rev_parse(pkg, 'HEAD')
            end

            it "acts on local_branch" do
                importer.import(pkg)
                head = importer.rev_parse(pkg, 'HEAD')
                importer.run_git(pkg, 'reset', '--hard', 'master~1')
                importer.run_git(pkg, 'branch', 'local')
                importer.local_branch = 'local'
                assert importer.import(pkg)
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

            it "updates the remote ref" do
                importer.import(pkg)
                importer.run_git(pkg, 'push', '--force', gitrepo, 'master~1:master')
                importer.import(pkg)
                expected = importer.rev_parse(pkg, 'master~1')
                assert_equal expected, importer.rev_parse(pkg, 'refs/remotes/autobuild/master')
            end

            it "updates the remote ref even if the update fails" do
                importer.import(pkg)
                importer.run_git(pkg, 'push', '--force', gitrepo, 'master~1:master')
                expected = importer.rev_parse(pkg, 'master~1')
                importer.run_git(pkg, 'reset', '--hard', 'master~2')
                File.open(File.join(tempdir, 'git', 'test'), 'a') do |io|
                    io.puts "test"
                end
                importer.run_git(pkg, 'commit', '-a', '-m', 'a fork commit')
                assert_raises(Autobuild::PackageException) do
                    importer.import(pkg)
                end
                assert_equal expected, importer.rev_parse(pkg, 'refs/remotes/autobuild/master')
            end

            it "switches to the local branch regardless of the presence of the tag or commit" do
                importer.import(pkg)
                head = importer.rev_parse(pkg, 'HEAD')
                importer.run_git(pkg, 'reset', '--hard', 'master~1')
                importer.run_git(pkg, 'branch', 'local')
                importer.local_branch = 'local'
                importer.relocate(importer.repository, tag: 'third_commit')
                assert importer.update(pkg)
                assert_equal 'refs/heads/local', importer.current_branch(pkg)
                assert_equal head, importer.rev_parse(pkg, 'refs/remotes/autobuild/master')
            end

            describe "the reset behaviour" do
                it "checks out the local branch even if its original state was diverged from the current commit" do
                    pin_importer 'fork'
                    assert importer.import(pkg)
                    assert_on_commit 'fork'
                end
                it "resets the local branch even if it diverged from the current commit" do
                    importer.import(pkg)
                    pin_importer 'fork'
                    assert importer.import(pkg, reset: true)
                    assert_on_commit 'fork'
                end
                it "refuses to reset the local branch if HEAD is not present remotely" do
                    importer.import(pkg)
                    File.open(File.join(tempdir, 'git', 'test'), 'a') do |io|
                        io.puts "test"
                    end
                    importer.run_git(pkg, 'commit', '-a', '-m', 'a fork commit')
                    new_head = importer.rev_parse(pkg, 'HEAD')
                    pin_importer 'fork'
                    assert_raises(Autobuild::ImporterCannotReset) do
                        importer.import(pkg, reset: true)
                    end
                    assert_equal new_head, importer.rev_parse(pkg, 'HEAD')
                end
                it "cleanly resets to the start state if local changes make the checkout abort" do
                    importer.import(pkg)
                    File.open(File.join(tempdir, 'git', 'test'), 'a') do |io|
                        io.puts "test"
                    end
                    pin_importer 'fork'
                    assert_raises(Autobuild::SubcommandFailed) do
                        importer.import(pkg, reset: true)
                    end
                    assert_on_commit 'tip'
                end
            end
        end
        describe "with a specific commit given" do
            before do
                @commits = nil
            end

            def assert_on_commit(id)
                assert_equal commits[id], importer.rev_parse(pkg, 'HEAD')
            end

            def commits
                unless @commits
                    importer = Autobuild.git(gitrepo)
                    pkg = Autobuild::Package.new 'commits'
                    pkg.srcdir = gitrepo
                    pkg.importer = importer
                    @commits = Hash[
                        'tip' => importer.rev_parse(pkg, 'master'),
                        'tip~1' => importer.rev_parse(pkg, 'master~1'),
                        'fork' => importer.rev_parse(pkg, 'fork'),
                    ]
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
                importer.relocate(extra_repo, commit: 'ba9ec170be55ba4675e2980b6e2da29a4c5797aa')
                assert importer.import(pkg, reset: false)
                assert_equal 'ba9ec170be55ba4675e2980b6e2da29a4c5797aa', importer.rev_parse(pkg, 'HEAD')
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
                importer.run_git_bare(pkg, 'tag', "tag0", "refs/heads/master")
                importer.run_git_bare(pkg, 'tag', "tag1", "refs/heads/master~1")
                importer.run_git_bare(pkg, 'tag', "forktag", "refs/heads/fork")
                @pins = Hash['tip' => 'tag0', 'tip~1' => 'tag1', 'fork' => 'forktag']
                @commits = Hash[
                    'tip' => importer.rev_parse(pkg, 'refs/heads/master'),
                    'tip~1' => importer.rev_parse(pkg, 'refs/heads/master~1'),
                    'fork' => importer.rev_parse(pkg, 'refs/heads/fork'),
                ]
            end

            def assert_on_commit(id)
                assert_equal commits[id], importer.rev_parse(pkg, 'HEAD')
            end

            def pin_importer(id, options = Hash.new)
                importer.relocate(importer.repository, options.merge(tag: @pins[id]))
            end

            it "fetches from the remote repository if the commit is not present locally" do
                importer.import(pkg)
                untar('gitrepo-with-extra-commit-and-tag.tar')
                extra_repo = File.join(tempdir, 'gitrepo-with-extra-commit-and-tag.git')
                importer.relocate(extra_repo, tag: 'extra_tag')
                assert importer.import(pkg, reset: false)
                tag_id = importer.rev_parse(pkg, 'extra_tag')
                assert_equal tag_id, importer.rev_parse(pkg, 'HEAD')
            end

            common_commit_and_tag_behaviour
        end
    end

    describe "submodule handling" do
        before do
            @master_root_commit = '8fc7584'
            tempdir = untar 'gitrepo-submodule-master.tar'
            untar 'gitrepo-submodule-child.tar'
            srcdir     = File.join(tempdir, 'gitrepo-submodule-master')
            @pkg       = Autobuild::Package.new 'submodule_test'
            pkg.srcdir = srcdir
            @importer  = Autobuild.git("#{srcdir}.git", with_submodules: true)
            pkg.importer = importer
        end

        describe "checkout" do
            it "checkouts submodules" do
                import
                assert_checkout_file_exist 'child', '.git'
                assert_equal "Commit 1\n", checkout_read('child', 'FILE')
            end
            it "checkouts submodules at the state of the tag/commit pin" do
                import commit: @master_root_commit
                assert_equal "Commit 0\n", checkout_read('child', 'FILE')
            end
            it "checkouts the submodule of the local branch" do
                import branch: 'a_branch'
                assert_equal "Commit 0\n", checkout_read('child', 'FILE')
            end
        end

        describe "update" do
            it "updates submodules" do
                import commit: @master_root_commit
                import commit: nil
                assert_equal "Commit 1\n", checkout_read('child', 'FILE')
            end
            it "does not update submodules in local-only mode" do
                import commit: @master_root_commit
                import commit: nil, local_only: true
                assert_equal "Commit 1\n", checkout_read('child', 'FILE')
            end
            it "updates submodules when checking out new branches" do
                import
                assert_equal "Commit 1\n", checkout_read('child', 'FILE')
                import branch: 'a_branch'
                assert_equal "Commit 0\n", checkout_read('child', 'FILE')
            end
            it "updates submodules when checking out existing branches" do
                import
                import branch: 'a_branch'
                import branch: 'master'
                assert_equal "Commit 1\n", checkout_read('child', 'FILE')
            end
            it "initializes new submodules" do
                import commit: @master_root_commit
                FileUtils.rm_rf checkout_path('commit1_submodule')
                import commit: nil
                assert_equal "Commit 1\n", checkout_read('commit1_submodule', 'FILE')
            end
        end

        describe "reset" do
            it "resets submodules" do
                import
                force_reset commit: @master_root_commit
                assert_equal "Commit 0\n", checkout_read('child', 'FILE')
            end
            it "initializes new submodules" do
                import
                refute_checkout_file_exist 'commit0_submodule'
                force_reset commit: @master_root_commit
                assert_equal "Commit 1\n", checkout_read('commit0_submodule', 'FILE')
            end
        end
    end

    describe "fingerprint generation" do
        before do
            importer.import(pkg)
            @expected_vcs_fingerprint = importer.rev_parse(pkg, 'HEAD')
        end
        it "returns the expected commit ID of HEAD" do
            assert_equal @expected_vcs_fingerprint, importer.fingerprint(pkg)
        end
        it "computes also the patches' fingerprint" do
            test_patches = [['/path/to/patch', 1, 'source_test'],['other/path', 2, 'source2_test']]
            flexmock(importer).
                should_receive(:currently_applied_patches).
                and_return(test_patches)
            flexmock(importer).
                should_receive(:patches).
                and_return(test_patches)

            # we expect paths will be ignored and the patches array to be
            # flatenned into a string
            expected_patch_fingerprint = Digest::SHA1.hexdigest('1source_test2source2_test')

            expected_fingerprint = Digest::SHA1.hexdigest(@expected_vcs_fingerprint +
                expected_patch_fingerprint)

            assert_equal expected_fingerprint, importer.fingerprint(pkg)
        end
    end

    def assert_checkout_file_exist(*file)
        assert File.exist?(checkout_path(*file))
    end

    def refute_checkout_file_exist(*file)
        refute File.exist?(checkout_path(*file))
    end

    def checkout_path(*file)
        File.join(pkg.srcdir, *file)
    end

    def checkout_read(*file)
        File.read(checkout_path(*file))
    end

    def force_reset(**options)
        importer.relocate(importer.repository, **options) unless options.empty?
        importer.import(pkg, reset: :force)
    end

    def import(**options)
        importer.relocate(importer.repository, **options) unless options.empty?
        importer.import(pkg)
    end
end

describe Autobuild::Git do
    attr_reader :pkg, :importer, :gitrepo
    before do
        tempdir = untar('gitrepo-nomaster.tar.xz')
        @gitrepo = File.join(tempdir, 'gitrepo-nomaster.git')
        @pkg = Autobuild::Package.new 'test'
        pkg.srcdir = File.join(tempdir, 'git')
        @importer = Autobuild.git(gitrepo)
        pkg.importer = importer
    end

    describe "Exist local branch before HEAD check" do
        it "get default remote brach" do
            Autobuild.silent = true
            assert_equal 'temp/branch', importer.default_remote_branch(pkg)
        end
        it "get default local brach" do
            Autobuild.silent = true
            importer.checkout(pkg)
            assert_equal 'temp/branch', importer.default_local_branch(pkg)
        end
        it "not call ls-remote if local existis on default call" do
            Autobuild.silent = true
            importer.checkout(pkg)
            flexmock(Autobuild::Subprocess)
                .should_receive(:run)
                .with(
                    any, :import, 'git', 'ls-remote', '--symref',
                    File.join(tempdir, 'gitrepo-nomaster.git'), any
                )
                .never()
                flexmock(Autobuild::Subprocess).should_receive(:run).pass_thru
            assert_equal 'temp/branch', importer.default_branch(pkg)
        end
        it "use default branch from repo" do
            Autobuild.silent = true
            importer.checkout(pkg)
            assert_equal 'temp/branch', importer.branch
        end
        it "local check if remote head exists" do
            flexmock(Autobuild::Subprocess)
                .should_receive(:run)
                .with(
                    any, :import, 'git', 'symbolic-ref', "refs/remotes/autobuild/HEAD", any
                )
                .once()
                .and_return(['ref: refs/heads/temp/branch HEAD', 'bla'])
            flexmock(Autobuild::Subprocess).should_receive(:run).pass_thru
            importer.import(pkg)
        end
    end
end

describe Autobuild::Git do
    attr_reader :pkg, :importer, :gitrepo
    before do
        tempdir = untar('gitrepo-nomaster.tar.xz')
        tempdir_local = untar('gitlocal-nomaster-singlenomaster.tar.xz')  # Single branch, no master
        @gitrepo = File.join(tempdir, 'gitrepo-nomaster.git')
        @pkg = Autobuild::Package.new 'test'
        pkg.srcdir = File.join(tempdir_local, 'gitrepo-nomaster')
        @importer = Autobuild.git(gitrepo)
        pkg.importer = importer
    end

    describe "Local single branch" do
        it "Return nil if local branch does not exists" do
            Autobuild.silent = true
            assert_equal nil, importer.default_local_branch(pkg)
        end
        it "get default remote brach if local does not exists" do
            Autobuild.silent = true
            assert_equal 'temp/branch', importer.default_branch(pkg)
        end
        it "shell out to git to check repo HEAD if not present on local branch" do
            flexmock(Autobuild::Subprocess)
                .should_receive(:run)
                .with(
                    any, :import, 'git', 'ls-remote', '--symref',
                    File.join(tempdir, 'gitrepo-nomaster.git'), any
                )
                .once()
                .and_return(['ref: refs/heads/temp/branch HEAD', 'bla'])
            flexmock(Autobuild::Subprocess).should_receive(:run).pass_thru
            importer.import(pkg)
            assert_equal 'temp/branch', importer.branch
        end
    end

end
