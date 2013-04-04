require 'fileutils'
require 'autobuild/subcommand'
require 'autobuild/importer'
require 'utilrb/kernel/options'

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
                Autobuild.warn "the git importer now expects you to provide the branch as a named option"
                Autobuild.warn "this form is deprecated:"
                Autobuild.warn "   Autobuild.git 'git://gitorious.org/rock/buildconf.git', 'master'"
                Autobuild.warn "and should be replaced by"
                Autobuild.warn "   Autobuild.git 'git://gitorious.org/rock/buildconf.git', :branch => 'master'"
            end

            gitopts, common = Kernel.filter_options options, :push_to => nil, :branch => nil, :tag => nil, :commit => nil
            if gitopts[:branch] && branch
                raise ConfigException, "git branch specified with both the option hash and the explicit parameter"
            end
            @push_to = gitopts[:push_to]
            branch = gitopts[:branch] || branch
            tag    = gitopts[:tag]
            commit = gitopts[:commit]

            @branch = branch || 'master'
            @tag    = tag
            @commit = commit
            super(common)
        end

        # Returns a string that identifies the remote repository uniquely
        #
        # This is meant for display purposes
        def repository_id
            "git:#{repository}"
        end

        # The remote repository URL.
        #
        # See also #push_to
        attr_accessor :repository

        # If set, this URL will be listed as a pushurl for the tracked branch.
        # It makes it possible to have a read-only URL for fetching and specify
        # a push URL for people that have commit rights
        #
        # #repository is always used for read-only operations
        attr_accessor :push_to

        # The remote branch to which we should push
        #
        # Defaults to #branch
        attr_writer :remote_branch

        # The branch this importer is tracking
        #
        # If set, both commit and tag have to be nil.
        attr_accessor :branch

        # The branch that should be used on the local clone
        #
        # If not set, it defaults to #branch
        attr_writer :local_branch

        # The branch that should be used on the local clone
        #
        # Defaults to #branch
        def local_branch
            @local_branch || branch
        end

        # The remote branch to which we should push
        #
        # Defaults to #branch
        def remote_branch
            @remote_branch || branch
        end

        # The tag we are pointing to. It is a tag name.
        #
        # If set, both branch and commit have to be nil.
        attr_reader :tag

        # The commit we are pointing to. It is a commit ID.
        #
        # If set, both branch and tag have to be nil.
        attr_reader :commit

        # True if it is allowed to merge remote updates automatically. If false
        # (the default), the import will fail if the updates do not resolve as
        # a fast-forward
        def merge?; !!@merge end

        # Set the merge flag. See #merge?
        def merge=(flag); @merge = flag end

        # Raises ConfigException if the current directory is not a git
        # repository
        def validate_importdir(package)
            if !File.directory?(File.join(package.importdir, '.git'))
                raise ConfigException.new(package, 'import'), "while importing #{package.name}, #{package.importdir} is not a git repository"
            end
        end

        # Fetches updates from the remote repository. Returns the remote commit
        # ID on success, nil on failure. Expects the current directory to be the
        # package's source directory.
        def fetch_remote(package)
            validate_importdir(package)
            Dir.chdir(package.importdir) do
                # If we are checking out a specific commit, we don't know which
                # branch to refer to in git fetch. So, we have to set up the
                # remotes and call git fetch directly (so that all branches get
                # fetch)
                #
                # Otherwise, do git fetch now
                #
                # Doing it now is better as it makes sure that we replace the
                # configuration parameters only if the repository and branch are
                # OK (i.e. we keep old working configuration instead)
                if branch || tag
                    Subprocess.run(package, :import, Autobuild.tool('git'), 'fetch', repository, branch || tag)
                elsif commit
                    Subprocess.run(package, :import, Autobuild.tool('git'), 'fetch', repository)
                end

                Subprocess.run(package, :import, Autobuild.tool('git'), 'config',
                               "--replace-all", "remote.autobuild.url", repository)
                if push_to
                    Subprocess.run(package, :import, Autobuild.tool('git'), 'config',
                                   "--replace-all", "remote.autobuild.pushurl", push_to)
                end
                Subprocess.run(package, :import, Autobuild.tool('git'), 'config',
                               "--replace-all", "remote.autobuild.fetch",  "+refs/heads/*:refs/remotes/autobuild/*")

                if remote_branch && local_branch
                    Subprocess.run(package, :import, Autobuild.tool('git'), 'config',
                               "--replace-all", "remote.autobuild.push",  "refs/heads/#{local_branch}:refs/heads/#{remote_branch}")
                else
                    Subprocess.run(package, :import, Autobuild.tool('git'), 'config',
                               "--replace-all", "remote.autobuild.push",  "refs/heads/*:refs/heads/*")
                end

                if local_branch
                    Subprocess.run(package, :import, Autobuild.tool('git'), 'config',
                                   "--replace-all", "branch.#{local_branch}.remote",  "autobuild")
                    Subprocess.run(package, :import, Autobuild.tool('git'), 'config',
                                   "--replace-all", "branch.#{local_branch}.merge", "refs/heads/#{local_branch}")
                end

                # Now get the actual commit ID from the FETCH_HEAD file, and
                # return it
                commit_id = if File.readable?( File.join('.git', 'FETCH_HEAD') )
                    fetch_commit = File.readlines( File.join('.git', 'FETCH_HEAD') ).
                        delete_if { |l| l =~ /not-for-merge/ }
                    if !fetch_commit.empty?
                        fetch_commit.first.split(/\s+/).first
                    end
                end

                # Update the remote tag if needs be
                if branch && commit_id
                    Subprocess.run(package, :import, Autobuild.tool('git'), 'update-ref',
                                   "-m", "updated by autobuild", "refs/remotes/autobuild/#{remote_branch}", commit_id)
                end

                commit_id
            end
        end

        # Returns a Importer::Status object that represents the status of this
        # package w.r.t. the root repository
        def status(package, only_local = false)
            Dir.chdir(package.importdir) do
                validate_importdir(package)
                remote_commit = nil
                if only_local
                    remote_commit = `git show-ref -s refs/remotes/autobuild/#{remote_branch}`.chomp
                else	
                    remote_commit =
                        begin fetch_remote(package)
                        rescue Exception => e
                            return fallback(e, package, :status, package, only_local)
                        end

                    if !remote_commit
                        return
                    end
                end

                status = merge_status(package, remote_commit)
                `git diff --quiet`
                if $?.exitstatus != 0
                    status.uncommitted_code = true
                end
                status
            end

        end

        def has_local_branch?
            `git show-ref -q --verify refs/heads/#{local_branch}`
            $?.exitstatus == 0
        end

        def detached_head?
            `git symbolic-ref HEAD -q`
            return ($?.exitstatus != 0)
        end

        # Checks if the current branch is the target branch. Expects that the
        # current directory is the package's directory
        def on_target_branch?
            current_branch = `git symbolic-ref HEAD -q`.chomp
            if $?.exitstatus != 0
                # HEAD cannot be resolved as a symbol. Assume that we are on a
                # detached HEAD
                return false
            end
            current_branch == "refs/heads/#{local_branch}"
        end

        class Status < Importer::Status
            attr_reader :fetch_commit
            attr_reader :head_commit
            attr_reader :common_commit

            def initialize(status, remote_commit, local_commit, common_commit)
                super()
                @status        = status
                @fetch_commit  = fetch_commit
                @head_commit   = head_commit
                @common_commit = common_commit

                if remote_commit != common_commit
                    @remote_commits = log(common_commit, remote_commit)
                end
                if local_commit != common_commit
                    @local_commits = log(common_commit, local_commit)
                end
            end

            def needs_update?
                status == Status::NEEDS_MERGE || status == Status::SIMPLE_UPDATE
            end

            def log(from, to)
                log = `git log --encoding=UTF-8 --pretty=format:"%h %cr %cn %s" #{from}..#{to}`.chomp

                if log.respond_to?(:encode)
                    log = log.encode
                end

                encodings = ['UTF-8', 'iso8859-1']
                begin
                    log.split("\n")
                rescue
                    if encodings.empty?
                        return "[some log messages have invalid characters, cannot display/parse them]"
                    end
                    log.force_encoding(encodings.pop)
                    retry
                end
            end
        end

        # Computes the update status to update a branch whose tip is at
        # reference_commit (which can be a symbolic reference) using the
        # fetch_commit commit
        #
        # I.e. this compute what happens if one would do
        #
        #   git checkout reference_commit
        #   git merge fetch_commit
        #
        def merge_status(package, fetch_commit, reference_commit = "HEAD")
            common_commit = `git merge-base #{reference_commit} #{fetch_commit}`.chomp
            if $?.exitstatus != 0
                raise PackageException.new(package, 'import'), "failed to find the merge-base between #{reference_commit} and #{fetch_commit}. Are you sure these commits exist ?"
            end
            head_commit   = `git rev-parse #{reference_commit}`.chomp
            if $?.exitstatus != 0
                raise PackageException.new(package, 'import'), "failed to resolve #{reference_commit}. Are you sure this commit, branch or tag exists ?"
            end

            status = if common_commit != fetch_commit
                         if common_commit == head_commit
                             Status::SIMPLE_UPDATE
                         else
                             Status::NEEDS_MERGE
                         end
                     else
                         if common_commit == head_commit
                             Status::UP_TO_DATE
                         else
                             Status::ADVANCED
                         end
                     end

            Status.new(status, fetch_commit, head_commit, common_commit)
        end

        def update(package)
            validate_importdir(package)
            Dir.chdir(package.importdir) do
                fetch_commit = fetch_remote(package)

                # If we are tracking a commit/tag, just check it out and return
                if commit || tag
                    target_commit = (commit || tag)
                    status_to_head = merge_status(package, target_commit, "HEAD")
                    if status_to_head.status == Status::UP_TO_DATE
                        # Check if by any chance we could switch back to a
                        # proper branch instead of having a detached HEAD
                        if detached_head?
                            status_to_remote = merge_status(package, target_commit, fetch_commit)
                            if status_to_remote.status != Status::UP_TO_DATE
                                package.message "  the package is on a detached HEAD because of commit pinning"
                                return
                            end
                        else
                            return
                        end
                    elsif status_to_head.status != Status::SIMPLE_UPDATE
                        raise PackageException.new(package, 'import'), "checking out the specified commit #{target_commit} would be a non-simple operation (i.e. the current state of the repository is not a linear relationship with the specified commit), do it manually"
                    end

                    status_to_remote = merge_status(package, target_commit, fetch_commit)
                    if status_to_remote.status != Status::UP_TO_DATE
                        # Try very hard to avoid creating a detached HEAD
                        if local_branch
                            status_to_branch = merge_status(package, target_commit, local_branch)
                            if status_to_branch.status == Status::UP_TO_DATE # Checkout the branch
                                package.message "  checking out specific commit %s for %s. It will checkout branch %s." % [target_commit.to_s, package.name, local_branch]
                                Subprocess.run(package, :import, Autobuild.tool('git'), 'checkout', local_branch)
                                return
                            end
                        end
                        package.message "  checking out specific commit %s for %s. This will create a detached HEAD." % [target_commit.to_s, package.name]
                        Subprocess.run(package, :import, Autobuild.tool('git'), 'checkout', target_commit)
                        return
                    end
                end

                if !fetch_commit
                    return
                end

                if !on_target_branch?
                    # Check if the target branch already exists. If it is the
                    # case, check it out. Otherwise, create it.
                    if system("git", "show-ref", "--verify", "--quiet", "refs/heads/#{local_branch}")
                        package.message "  switching branch of %s to %s" % [package.name, local_branch]
                        Subprocess.run(package, :import, Autobuild.tool('git'), 'checkout', local_branch)
                    else
                        package.message "  checking out branch %s for %s" % [local_branch, package.name]
                        Subprocess.run(package, :import, Autobuild.tool('git'), 'checkout', '-b', local_branch, "FETCH_HEAD")
                    end
                end

                status = merge_status(package, fetch_commit)
                if status.needs_update?
                    if !merge? && status.status == Status::NEEDS_MERGE
                        raise PackageException.new(package, 'import'), "the local branch '#{local_branch}' and the remote branch #{branch} of #{package.name} have diverged, and I therefore refuse to update automatically. Go into #{package.importdir} and either reset the local branch or merge the remote changes"
                    end
                    Subprocess.run(package, :import, Autobuild.tool('git'), 'merge', fetch_commit)
                end
            end
        end

        def checkout(package)
            base_dir = File.expand_path('..', package.importdir)
            if !File.directory?(base_dir)
                FileUtils.mkdir_p base_dir
            end

            Subprocess.run(package, :import,
                Autobuild.tool('git'), 'clone', '-o', 'autobuild', repository, package.importdir)

            Dir.chdir(package.importdir) do
                if push_to
                    Subprocess.run(package, :import, Autobuild.tool('git'), 'config',
                                   "--replace-all", "remote.autobuild.pushurl", push_to)
                end
                if local_branch && remote_branch
                    Subprocess.run(package, :import, Autobuild.tool('git'), 'config',
                                   "--replace-all", "remote.autobuild.push", "refs/heads/#{local_branch}:refs/heads/#{remote_branch}")
                end

                # If we are tracking a commit/tag, just check it out
                if commit || tag
                    status = merge_status(package, commit || tag)
                    if status.status != Status::UP_TO_DATE
                        package.message "  checking out specific commit for %s. This will create a detached HEAD." % [package.name]
                        Subprocess.run(package, :import, Autobuild.tool('git'), 'checkout', commit || tag)
                    end
                else
                    current_branch = `git symbolic-ref HEAD`.chomp
                    if current_branch == "refs/heads/#{local_branch}"
                        Subprocess.run(package, :import, Autobuild.tool('git'),
                            'reset', '--hard', "autobuild/#{branch}")
                    else
                        Subprocess.run(package, :import, Autobuild.tool('git'),
                            'checkout', '-b', local_branch, "autobuild/#{branch}")
                    end
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

