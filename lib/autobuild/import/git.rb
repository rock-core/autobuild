require 'fileutils'
require 'autobuild/subcommand'
require 'autobuild/importer'
require 'utilrb/kernel/options'

module Autobuild
    class Git < Importer
        class << self
            # Sets the default alternates path used by all Git importers
            #
            # Setting it explicitly overrides any value we get from the
            # AUTOBUILD_CACHE_DIR and AUTOBUILD_GIT_CACHE_DIR environment
            # variables.
            #
            # @see default_alternates
            attr_writer :default_alternates

            # A default list of repositories that should be used as reference
            # repositories for all Git importers
            #
            # It is initialized (by order of priority) using the
            # AUTOBUILD_GIT_CACHE_DIR and AUTOBUILD_CACHE_DIR environment
            # variables
            #
            # @return [Array]
            # @see default_alternates=, Git#alternates
            def default_alternates
                if @default_alternates then @default_alternates
                elsif cache_dir = ENV['AUTOBUILD_GIT_CACHE_DIR']
                    @default_alternates = cache_dir.split(':').map { |path| File.expand_path(path) }
                elsif cache_dir = ENV['AUTOBUILD_CACHE_DIR']
                    @default_alternates = cache_dir.split(':').map { |path| File.join(File.expand_path(path), 'git', '%s') }
                else Array.new
                end
            end
        end

        # Creates an importer which tracks the given repository
        # and branch. +source+ is [repository, branch]
        #
        # This importer uses the 'git' tool to perform the
        # import. It defaults to 'git' and can be configured by
        # doing 
	#   Autobuild.programs['git'] = 'my_git_tool'
        def initialize(repository, branch = nil, options = {})
            @repository = repository.to_str
            @alternates = Git.default_alternates.dup
            @git_dir_cache = Array.new

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

            gitopts, common = Kernel.filter_options options, :push_to => nil, :branch => nil, :tag => nil, :commit => nil, :with_submodules => false
            if gitopts[:branch] && branch
                raise ConfigException, "git branch specified with both the option hash and the explicit parameter"
            end
            @push_to = gitopts[:push_to]
            @with_submodules = gitopts[:with_submodules]
            branch = gitopts[:branch] || branch
            tag    = gitopts[:tag]
            commit = gitopts[:commit]

            @branch = branch || 'master'
            @tag    = tag
            @commit = commit
            @remote_name = 'autobuild'
            super(common)
        end

        # Returns a string that identifies the remote repository uniquely
        #
        # This is meant for display purposes
        def repository_id
            "git:#{repository}"
        end

        # The name of the remote that should be set up by the importer
        #
        # Defaults to 'autobuild'
        attr_accessor :remote_name

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

        # Set to true if checkout should be done with submodules
        #
        # Defaults to #false
        attr_writer :with_submodules

        # The branch this importer is tracking
        #
        # If set, both commit and tag have to be nil.
        attr_accessor :branch

        # The branch that should be used on the local clone
        #
        # If not set, it defaults to #branch
        attr_writer :local_branch

        # A list of local (same-host) repositories that will be used instead of
        # the remote one when possible. It has one major issue (see below), so
        # use at your own risk.
        #
        # The paths must point to the git directory, so either the .git
        # directory in a checked out git repository, or the repository itself in
        # a bare repository.
        #
        # A default reference repository can be given through the
        # AUTOBUILD_GIT_CACHE environment variable.
        #
        # Note that it has the major caveat that if objects disappear from the
        # reference repository, the current one will be broken. See the git
        # documentation for more information.
        #
        # @return [Array<String>]
        attr_accessor :alternates

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

        #Return true if the git checkout should be done with submodules
        #detaul it false
        def with_submodules?; !!@with_submodules end

        # Set the merge flag. See #merge?
        def merge=(flag); @merge = flag end

        # Raises ConfigException if the current directory is not a git
        # repository
        def validate_importdir(package)
            return git_dir(package, true)
        end

        # Resolves the git directory associated with path, and tells whether it
        # is a bare repository or not
        #
        # @param [String] path the path from which we should resolve
        # @return [(String,Symbol),nil] either the path to the git folder and
        #  :bare or :normal, or nil if path is not a git repository.
        def self.resolve_git_dir(path)
            dir = File.join(path, '.git')
            if !File.exists?(dir)
                dir = path
            end

            result = `#{Autobuild.tool(:git)} --git-dir="#{dir}" rev-parse --is-bare-repository`
            if $?.success?
                if result.strip == "true"
                    return dir, :bare
                else return dir, :normal
                end
            end
        end

        def git_dir(package, require_working_copy)
            if @git_dir_cache[0] == package.importdir
                dir, style = *@git_dir_cache[1, 2]
            else
                dir, style = Git.resolve_git_dir(package.importdir)
            end

            @git_dir_cache = [package.importdir, dir, style]
            if !style
                raise ConfigException.new(package, 'import'), "while importing #{package.name}, #{package.importdir} does not point to a git repository"
            elsif require_working_copy && (style == :bare)
                raise ConfigException.new(package, 'import'), "while importing #{package.name}, #{package.importdir} points to a bare git repository but a working copy was required"
            else
                return dir
            end
        end

        # Computes the merge status for this package between two existing tags
        # Raises if a tag is unknown
        def delta_between_tags(package, from_tag, to_tag)
            Dir.chdir(package.importdir) do
                pkg_tags = tags(package)
                if not pkg_tags.has_key?(from_tag)
                    raise ArgumentError, "tag '#{from_tag}' is unknown to #{package.name} -- known tags are: #{pkg_tags.keys}"
                end
                if not pkg_tags.has_key?(to_tag)
                    raise ArgumentError, "tag '#{to_tag}' is unknown to #{package.name} -- known tags are: #{pkg_tags.keys}"
                end

                from_commit = pkg_tags[from_tag]
                to_commit = pkg_tags[to_tag]

                merge_status(package, to_commit, from_commit)
           end
        end

        # Retrieve the tags of this packages as a hash mapping to the commit id
        def tags(package)
            Dir.chdir(package.importdir) do
                `git fetch --tags -q`
                tag_list = `git show-ref --tags`
                tag_list = tag_list.split("\n")
                @tags ||= Hash.new
                tag_list.each do |entry|
                    commit_to_tag = entry.split(" ")
                    @tags[commit_to_tag[1].sub("refs/tags/","")] = commit_to_tag[0]
                end
                @tags
            end
        end

        def update_cache(package, cache_dir, phase)
            remote_name = package.name.gsub(/[^\w]/, '_')
            Subprocess.run(*git, "remote.#{remote_name}.url", repository)
            Subprocess.run(*git, "remote.#{remote_name}.fetch",  "+refs/heads/*:refs/remotes/#{remote_name}/*")
            Subprocess.run(*git, 'fetch', '--tags', remote_name)
        end

        # Updates the git repository's configuration for the target remote
        def update_remotes_configuration(package, phase)
            git = [package, phase, Autobuild.tool(:git), '--git-dir', git_dir(package, false), 'config', '--replace-all']
            Subprocess.run(*git, "remote.#{remote_name}.url", repository)
            if push_to
                Subprocess.run(*git, "remote.#{remote_name}.pushurl", push_to)
            end
            Subprocess.run(*git, "remote.#{remote_name}.fetch",  "+refs/heads/*:refs/remotes/#{remote_name}/*")

            if remote_branch && local_branch
                Subprocess.run(*git, "remote.#{remote_name}.push",  "refs/heads/#{local_branch}:refs/heads/#{remote_branch}")
            else
                Subprocess.run(*git, "remote.#{remote_name}.push",  "refs/heads/*:refs/heads/*")
            end

            if local_branch
                Subprocess.run(*git, "branch.#{local_branch}.remote",  remote_name)
                Subprocess.run(*git, "branch.#{local_branch}.merge", "refs/heads/#{local_branch}")
            end
        end

        # Fetches updates from the remote repository. Returns the remote commit
        # ID on success, nil on failure. Expects the current directory to be the
        # package's source directory.
        def fetch_remote(package)
            validate_importdir(package)
            git_dir = git_dir(package, false)
            git = [package, :import, Autobuild.tool('git'), '--git-dir', git_dir]

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
            refspec = [branch || tag].compact
            Subprocess.run(*git, 'fetch', '--tags', repository, *refspec)

            update_remotes_configuration(package, :import)

            # Now get the actual commit ID from the FETCH_HEAD file, and
            # return it
            commit_id = if File.readable?( File.join(git_dir, 'FETCH_HEAD') )
                fetch_commit = File.readlines( File.join(git_dir, 'FETCH_HEAD') ).
                    delete_if { |l| l =~ /not-for-merge/ }
                if !fetch_commit.empty?
                    fetch_commit.first.split(/\s+/).first
                end
            end

            # Update the remote tag if needs be
            if branch && commit_id
                Subprocess.run(*git, 'update-ref',
                               "-m", "updated by autobuild", "refs/remotes/#{remote_name}/#{remote_branch}", commit_id)
            end

            commit_id
        end

        # Returns a Importer::Status object that represents the status of this
        # package w.r.t. the root repository
        def status(package, only_local = false)
            Dir.chdir(package.importdir) do
                validate_importdir(package)
                remote_commit = nil
                if only_local
                    remote_commit = `git show-ref -s refs/remotes/#{remote_name}/#{remote_branch}`.chomp
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

        def current_branch
            current_branch = `git symbolic-ref HEAD -q`.chomp
            if $?.exitstatus != 0
                # HEAD cannot be resolved as a symbol. We are probably on a
                # detached HEAD
                return
            end
            return current_branch
        end

        # Checks if the current branch is the target branch. Expects that the
        # current directory is the package's directory
        def on_target_branch?
            if current_branch = self.current_branch
                current_branch == "refs/heads/#{local_branch}"
            end
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

        # Updates the git alternates file in the already checked out package to
        # match {#alternates}
        #
        # @param [Package] package the already checked-out package
        # @return [void]
        def update_alternates(package)
            alternates_path = File.join(git_dir(package, false), 'objects', 'info', 'alternates')
            current_alternates =
                if File.file?(alternates_path)
                    File.readlines(alternates_path).map(&:strip).find_all { |l| !l.empty? }
                else Array.new
                end

            alternates = each_alternate_path(package).map do |path|
                File.join(path, 'objects')
            end

            if current_alternates.sort != alternates.sort
                # Warn that something is fishy, but assume that the user knows
                # what he is doing
                package.warn "%s: the list of git alternates listed in the repository differs from the one set up in autobuild."
                package.warn "%s: I will update, but that is dangerous"
                package.warn "%s: using git alternates is for advanced users only, who know git very well."
                package.warn "%s: Don't complain if something breaks"
            end
            if alternates.empty?
                FileUtils.rm_f alternates_path
            else
                File.open(alternates_path, 'w') do |io|
                    io.write alternates.join("\n")
                end
            end
        end

        def update(package,only_local = false)
            validate_importdir(package)
            update_alternates(package)
            Dir.chdir(package.importdir) do
                #Checking if we should only merge our repro to remotes/HEAD without updateing from the remote side...
                if !only_local
                    fetch_commit = fetch_remote(package)
                end

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

        def each_alternate_path(package)
            return enum_for(__method__, package) if !block_given?

            alternates.each do |path|
                path = path % [package.name]
                if File.directory?(path)
                    yield(path)
                end
            end
            nil
        end

        def checkout(package)
            base_dir = File.expand_path('..', package.importdir)
            if !File.directory?(base_dir)
                FileUtils.mkdir_p base_dir
            end

            clone_options = ['-o', remote_name]

            if with_submodules?
                clone_options << '--recurse-submodules'
            end
            each_alternate_path(package) do |path|
                clone_options << '--reference' << path
            end
            Subprocess.run(package, :import,
                Autobuild.tool('git'), 'clone', *clone_options, repository, package.importdir)

            Dir.chdir(package.importdir) do
                if push_to
                    Subprocess.run(package, :import, Autobuild.tool('git'), 'config',
                                   "--replace-all", "remote.#{remote_name}.pushurl", push_to)
                end
                if local_branch && remote_branch
                    Subprocess.run(package, :import, Autobuild.tool('git'), 'config',
                                   "--replace-all", "remote.#{remote_name}.push", "refs/heads/#{local_branch}:refs/heads/#{remote_branch}")
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
                            'reset', '--hard', "#{remote_name}/#{branch}")
                    else
                        Subprocess.run(package, :import, Autobuild.tool('git'),
                            'checkout', '-b', local_branch, "#{remote_name}/#{branch}")
                    end
                end
            end
        end

        # Changes the repository this importer is pointing to
        def relocate(repository)
            @repository = repository
        end

        # Tests whether the given directory is a git repository
        def self.can_handle?(path)
            _, style = Git.resolve_git_dir(path)
            style == :normal
        end

        # Returns a hash that represents the configuration of a git importer
        # based on the information contained in the git configuration
        #
        # @raise [ArgumentError] if the path does not point to a git repository
        def self.vcs_definition_for(path)
            if !can_handle?(path)
                raise ArgumentError, "#{path} is either not a git repository, or a bare git repository"
            end

            Dir.chdir(path) do
                vars = `git config -l`.
                    split("\n").
                    inject(Hash.new) do |h, line|
                        k, v = line.strip.split('=', 2)
                        h[k] = v
                        h
                    end
                url = vars["remote.#{remote_name}.url"] ||
                    vars['remote.origin.url']
                if url
                    return Hash[:type => :git, :url => url]
                else
                    return Hash[:type => :git]
                end
            end
        end
    end

    # Creates a git importer which gets the source for the given repository and branch
    # URL +source+.
    def self.git(repository, branch = nil, options = {})
        Git.new(repository, branch, options)
    end
end

