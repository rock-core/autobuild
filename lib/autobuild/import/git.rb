require 'fileutils'
require 'autobuild/subcommand'
require 'autobuild/importer'

module Autobuild
    class Git < Importer
        # Creates an importer which tracks the given repository
        # and branch. +source+ is [repository, branch]
        #
        # This importer uses the 'git' tool to perform the
        # import. It defaults to 'svn' and can be configured by
        # doing 
	#   Autobuild.programs['git'] = 'my_git_tool'
        def initialize(repository, branch = nil, options = {})
            @repository = repository.to_str

            if branch.respond_to?(:to_hash)
                options = branch.to_hash
                branch = nil
            end

            if branch
                STDERR.puts "WARN: the git importer now expects you to provide the branch as a named option"
                STDERR.puts "WARN: this form is deprecated:"
                STDERR.puts "WARN:    Autobuild.git 'git://github.com/doudou/autobuild.git', 'master'"
                STDERR.puts "WARN: and should be replaced by"
                STDERR.puts "WARN:    Autobuild.git 'git://github.com/doudou/autobuild.git', :branch => 'master'"
            end

            gitopts, common = Kernel.filter_options options, :branch => 'master', :tag => nil, :commit => nil
            if gitopts[:branch] && branch
                raise ConfigException, "git branch specified with both the option hash and the explicit parameter"
            end
            branch = gitopts[:branch] || branch
            tag    = gitopts[:tag]
            commit = gitopts[:commit]

            if (branch && commit) || (branch && commit) || (tag && commit)
                raise ConfigException, "you can specify only a branch, tag or commit but not two or three at the same time"
            end
            @branch = branch
            @commit = tag || commit
            super(common)
        end

        attr_accessor :repository

        # The branch this importer is tracking
        #
        # If set, tag has to be nil.
        attr_accessor :branch
        # The commit we are pointing to. It can be either a commit ID or a tag
        # name. 
        #
        # If set, branch has to be nil.
        attr_reader :commit

        # True if it is allowed to merge remote updates automatically. If false
        # (the default), the import will fail if the updates do not resolve as
        # a fast-forward
        def merge?; !!@merge end

        # Set the merge flag. See #merge?
        def merge=(flag); @merge = flag end

        # Raises ConfigException if the current directory is not a git
        # repository
        def validates_git_repository
            if !File.directory?('.git')
                raise ConfigException, "#{package.srcdir} is not a git repository"
            end
        end

        # Fetches updates from the remote repository. Returns the remote commit
        # ID on success, nil on failure. Expects the current directory to be the
        # package's source directory.
        def fetch_remote(package)
            Dir.chdir(package.srcdir) do
                validates_git_repository

                Subprocess.run(package.name, :import, Autobuild.tool('git'), 'fetch', repository, branch)
                if File.readable?( File.join('.git', 'FETCH_HEAD') )
                    fetch_commit = File.readlines( File.join('.git', 'FETCH_HEAD') ).
                        delete_if { |l| l =~ /not-for-merge/ }
                    if !fetch_commit.empty?
                        fetch_commit.first.split(/\s+/).first
                    end
                end
            end
        end

        # Returns a Importer::Status object that represents the status of this
        # package w.r.t. the root repository
        def status(package)
            Dir.chdir(package.srcdir) do
                remote_commit = fetch_remote(package)
                if !remote_commit
                    return
                end

                status = merge_status(remote_commit)
                if status.needs_update?
                    commits = fetch_commits_between(status.common, status.remote)
                    if status.status == UPDATE_FAST_FORWARD
                        Importer::Status.update(commits)
                    else
                        Importer::Status.merge(commits)
                    end
                elsif status.status == UPDATE_ADVANCED
                    Importer::Status.advanced(fetch_commits_between(status.common, status.local))
                else
                    Importer::Status.up_to_date
                end
            end
        end

        # Checks if the current branch is the target branch. Expects that the
        # current directory is the package's directory
        def on_target_branch?
            current_branch = `git symbolic-ref HEAD`.chomp
            current_branch == "refs/heads/#{branch}"
        end

        MergeStatus = Struct.new :status, :remote, :local, :common
        class MergeStatus
            def needs_update?
                status == UPDATE_FAST_FORWARD || status == UPDATE_MERGE
            end
        end

        UPDATE_FAST_FORWARD = 1
        UPDATE_MERGE        = 2
        UPDATE_SYNC         = 3
        UPDATE_ADVANCED     = 4

        def merge_status(fetch_commit)
            common_commit = `git merge-base HEAD #{fetch_commit}`.chomp
            head_commit   = `git rev-parse #{branch}`.chomp

            status = if common_commit != fetch_commit
                         if common_commit == head_commit
                             UPDATE_FAST_FORWARD
                         else
                             UPDATE_MERGE
                         end
                     else
                         if common_commit == head_commit
                             UPDATE_SYNC
                         else
                             UPDATE_ADVANCED
                         end
                     end

            MergeStatus.new(status, fetch_commit, head_commit, common_commit)
        end

        def update(package)
            Dir.chdir(package.srcdir) do
                validates_git_repository
                fetch_commit = fetch_remote(package)
                if !fetch_commit
                    return
                end

                # If we are tracking a commit/tag, just check it out and return
                if commit
                    Subprocess.run(package.name, :import, Autobuild.tool('git'), 'checkout', commit)
                    return
                end

                if !on_target_branch?
                    # Check if the target branch already exists. If it is the
                    # case, check it out. Otherwise, create it.
                    if File.file?(File.join(".git", "refs", "heads", branch))
                        Subprocess.run(package.name, :import, Autobuild.tool('git'), 'checkout', branch)
                    else
                        Subprocess.run(package.name, :import, Autobuild.tool('git'), 'checkout', '-b', branch, "FETCH_HEAD")
                    end
                end

                status = merge_status(fetch_commit)
                if status.needs_update?
                    if !merge? && status.status == UPDATE_MERGE
                        raise PackageException, "importing the current version would require a merge"
                    end
                    Subprocess.run(package.name, :import, Autobuild.tool('git'), 'merge', fetch_commit)
                end
            end
        end

        def checkout(package)
            base_dir = File.expand_path('..', package.srcdir)
            if !File.directory?(base_dir)
                FileUtils.mkdir_p base_dir
            end

            Subprocess.run(package.name, :import,
                Autobuild.tool('git'), 'clone', '-o', 'autobuild',
                repository, package.srcdir)

            Dir.chdir(package.srcdir) do
                # If we are tracking a commit/tag, just check it out
                if commit
                    Subprocess.run(package.name, :import, Autobuild.tool('git'),
                        'checkout', commit)
                    return
                end

                current_branch = `git symbolic-ref HEAD`.chomp
                if current_branch == "refs/heads/#{branch}"
                    Subprocess.run(package.name, :import, Autobuild.tool('git'),
                    'reset', '--hard', "autobuild/#{branch}")
                else
                    Subprocess.run(package.name, :import, Autobuild.tool('git'),
                    'checkout', '-b', branch, "autobuild/#{branch}")
                end
            end
        end
    end

    # Creates a git importer which gets the source for the given repository and branch
    # URL +source+. The allowed values in +options+ are described in SVN.new.
    def self.git(repository, branch = nil, options = {})
        Git.new(repository, branch, options)
    end
end

