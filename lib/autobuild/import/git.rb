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
                elsif cache_dirs = Importer.cache_dirs('git')
                    @default_alternates = cache_dirs.map { |path| File.join(File.expand_path(path), '%s') }
                else Array.new
                end
            end
        end

        self.default_alternates = nil

        # Returns the git version as a string
        #
        # @return [String]
        def self.version
            version = Subprocess.run('git', 'setup', Autobuild.tool(:git), '--version').first
            if version =~ /^git version (\d[\d\.]+)/
                $1.split(".").map { |i| Integer(i) }
            else
                raise ArgumentError, "cannot parse git version string #{version}, was expecting something looking like 'git version 2.1.0'"
            end
        end

        # Helper method to compare two (partial) versions represented as array
        # of integers
        #
        # @return [Integer] -1 if actual is greater than required, 
        #   0 if equal, and 1 if actual is smaller than required
        def self.compare_versions(actual, required)
            if actual.size > required.size
                return -compare_versions(required, actual)
            end

            actual += [0] * (required.size - actual.size)
            actual.zip(required).each do |v_act, v_req|
                if v_act > v_req then return -1
                elsif v_act < v_req then return 1
                end
            end
            0
        end

        # Tests the git version
        #
        # @param [Array<Integer>] version the git version as an array of integer
        # @return [Boolean] true if the git version is at least the requested
        #   one, and false otherwise
        def self.at_least_version(*version)
            compare_versions(self.version, version) <= 0
        end

        # Creates an importer which tracks a repository and branch.
        #
        # This importer uses the 'git' tool to perform the import. It defaults
        # to 'git' and can be configured by doing 
        #
	#   Autobuild.programs['git'] = 'my_git_tool'
        #
        # @param [String] branch deprecated, use the 'branch' named option
        #   instead
        #
        # @option options [String] push_to (repository) the URL to set up as push_to URL in
        #   the remote(s). Note that it is not used internally by this class
        # @option options [String] branch (master) the branch we should track. It is used
        #   both as {#local_branch} and {#remote_branch}
        # @option options [String] tag (nil) a tag at which we should pin the
        #   checkout. Cannot be given at the same time than :commit
        # @option options [String] commit (nil) a commit ID at which we should pin the
        #   checkout. Cannot be given at the same time than :tag
        # @option options [String] repository_id (git:#{repository}) a string that allows to
        #   uniquely identify a repository. The meaning is caller-specific. For
        #   instance, autoproj uses repository_id to check whether two Git
        #   importers fetches from the same repository.
        # @option options [Boolean] with_submodules (false) whether the importer should
        #   checkout and update submodules. Note that in an autobuild-based
        #   workflow, it is recommended to not use submodules but checkout all
        #   repositories separately instead.
        def initialize(repository, branch = nil, options = {})
            @alternates = Git.default_alternates.dup
            @git_dir_cache = Array.new
            @local_branch = @remote_branch = nil
            @tag = @commit = nil

            @merge = false

            if branch.respond_to?(:to_hash)
                branch, options = nil, branch.to_hash
            end

            if branch
                Autobuild.warn "the git importer now expects you to provide the branch as a named option"
                Autobuild.warn "this form is deprecated:"
                Autobuild.warn "   Autobuild.git 'git://gitorious.org/rock/buildconf.git', 'master'"
                Autobuild.warn "and should be replaced by"
                Autobuild.warn "   Autobuild.git 'git://gitorious.org/rock/buildconf.git', :branch => 'master'"
            end

            gitopts, common = Kernel.filter_options options,
                push_to: nil,
                branch: nil,
                tag: nil,
                commit: nil,
                repository_id: nil,
                source_id: nil,
                with_submodules: false
            if gitopts[:branch] && branch
                raise ConfigException, "git branch specified with both the option hash and the explicit parameter"
            end
            gitopts[:branch] ||= branch

            super(common)

            @with_submodules = gitopts.delete(:with_submodules)
            @remote_name = 'autobuild'
            @push_to = nil
            relocate(repository, gitopts)
            @additional_remotes = Array.new
        end

        # The name of the remote that should be set up by the importer
        #
        # Defaults to 'autobuild'
        attr_accessor :remote_name

        # The remote repository URL.
        #
        # @see push_to
        attr_accessor :repository

        # If set, this URL will be listed as a pushurl for the tracked branch.
        # It makes it possible to have a read-only URL for fetching and specify
        # a push URL for people that have commit rights
        #
        # It is not used by the importer itself
        #
        # {#repository} is always used for read-only operations
        attr_accessor :push_to

        # Set to true if checkout should be done with submodules
        #
        # Defaults to false
        attr_writer :with_submodules

        # The branch this importer is tracking
        attr_accessor :branch

        # Set {#local_branch}
        attr_writer :local_branch

        # Set {#remote_branch}
        attr_writer :remote_branch

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

        # A list of remotes that should be set up in the git config
        #
        # Use {#declare_alternate_repository} to add one
        #
        # @return [(String,String,String)] a list of (name, repository, push_to)
        #   triplets
        attr_reader :additional_remotes

        # The branch that should be used on the local clone
        #
        # Defaults to {#branch}
        def local_branch
            @local_branch || branch
        end

        # The remote branch to which we should push
        #
        # Defaults to {#branch}
        def remote_branch
            @remote_branch || branch
        end

        # The tag we are pointing to. It is a tag name.
        #
        # Setting it through this method is deprecated, use {#relocate} to set
        # the tag
        attr_accessor :tag

        # The commit we are pointing to. It is a commit ID.
        #
        # Setting it through this method is deprecated, use {#relocate} to set
        # the commit
        attr_accessor :commit

        # True if it is allowed to merge remote updates automatically. If false
        # (the default), the import will fail if the updates do not resolve as
        # a fast-forward
        def merge?; !!@merge end

        # Set the merge flag. See #merge?
        def merge=(flag); @merge = flag end

        # Whether the git checkout should be done with submodules
        def with_submodules?; !!@with_submodules end

        # @api private
        #
        # Verifies that the package's {Package#importdir} points to a git
        # repository
        def validate_importdir(package)
            return git_dir(package, true)
        end

        # @api private
        #
        # Resolves the git directory associated with path, and tells whether it
        # is a bare repository or not
        #
        # @param [String] path the path from which we should resolve
        # @return [(String,Symbol),nil] either the path to the git folder and
        #  :bare or :normal, or nil if path is not a git repository.
        def self.resolve_git_dir(path)
            dir = File.join(path, '.git')
            if !File.exist?(dir)
                dir = path
            end

            result = `#{Autobuild.tool(:git)} --git-dir="#{dir}" rev-parse --is-bare-repository 2>&1`
            if $?.success?
                if result.strip == "true"
                    return dir, :bare
                else return dir, :normal
                end
            end
        end

        # @api private
        #
        # Returns either the package's working copy or git directory
        #
        # @param [Package] package the package to resolve
        # @param [Boolean] require_working_copy whether a working copy is
        #   required
        # @raise if the package's {Package#importdir} is not a git repository,
        #   or if it is a bare repository and require_working_copy is true
        def git_dir(package, require_working_copy)
            if @git_dir_cache[0] == package.importdir
                dir, style = *@git_dir_cache[1, 2]
            else
                dir, style = Git.resolve_git_dir(package.importdir)
            end

            @git_dir_cache = [package.importdir, dir, style]
            self.class.validate_git_dir(package, require_working_copy, dir, style)
            dir
        end

        # @api private
        #
        # (see Git#git_dir)
        def self.git_dir(package, require_working_copy)
            dir, style = Git.resolve_git_dir(package.importdir)
            validate_git_dir(package, require_working_copy, dir, style)
            dir
        end

        # @api private
        #
        # Validates the return value of {resolve_git_dir}
        #
        # @param [Package] package the package we are working on
        # @param [Boolean] require_working_copy if false, a bare repository will
        #   be considered as valid, otherwise not
        # @param [String,nil] dir the path to the repository's git directory, or nil
        #   if the target is not a valid repository (see the documentation of
        #   {resolve_git_dir}
        # @param [Symbol,nil] style either :normal for a git checkout with
        #   working copy, :bare for a bare repository or nil if {resolve_git_dir}
        #   did not detect a git repository
        #
        # @return [void]
        # @raise ConfigException if dir/style are nil, or if
        #   require_working_copy is true and style is :bare
        def self.validate_git_dir(package, require_working_copy, dir, style)
            if !style
                raise ConfigException.new(package, 'import', retry: false),
                    "while importing #{package.name}, #{package.importdir} does not point to a git repository"
            elsif require_working_copy && (style == :bare)
                raise ConfigException.new(package, 'import', retry: false),
                    "while importing #{package.name}, #{package.importdir} points to a bare git repository but a working copy was required"
            end
        end

        # Computes the merge status for this package between two existing tags
        #
        # @param [Package] package
        # @param [String] from_tag the source tag
        # @param [String] to_tag the target tag
        # @raise [ArgumentError] if one of the tags is unknown
        def delta_between_tags(package, from_tag, to_tag)
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

        # The tags of this packages
        #
        # @param [Package] package
        # @option options [Boolean] only_local (false) whether the tags should
        #   be fetch from the remote first, or if one should only list tags that
        #   are already known locally 
        # @return [Hash<String,String>] a mapping from a tag name to its commit
        #   ID
        def tags(package, options = Hash.new)
            if !options.fetch(only_local: false)
                run_git_bare(package, 'fetch', '--tags')
            end
            tag_list = run_git_bare(package, 'show-ref', '--tags').map(&:strip)
            tags = Hash.new
            tag_list.each do |entry|
                commit_to_tag = entry.split(" ")
                tags[commit_to_tag[1].sub("refs/tags/","")] = commit_to_tag[0]
            end
            tags
        end

        # @api private
        #
        # Run a git command that require a working copy
        #
        # @param [Package] package
        # @param [Array] args the git arguments, excluding the git command
        #   itself. The last argument can be a hash, in which case it is passed
        #   as an option hash to {Package#run}
        def run_git(package, *args)
            self.class.run_git(package, *args)
        end

        # @api private
        #
        # (see Git#run_git)
        def self.run_git(package, *args)
            options = Hash.new
            if args.last.kind_of?(Hash)
                options = args.pop
            end

            working_directory = File.dirname(git_dir(package, true))
            package.run(:import, Autobuild.tool(:git), *args,
                        Hash[resolved_env: Hash.new, working_directory: working_directory].merge(options))
        end

        # @api private
        #
        # Run a git command that only need a git directory
        #
        # @param (see Git#run_git)
        def run_git_bare(package, *args)
            self.class.run_git_bare(package, *args)
        end

        # @api private
        #
        # (see Git#run_git_bare)
        def self.run_git_bare(package, *args)
            options = Hash.new
            if args.last.kind_of?(Hash)
                options = args.pop
            end
            package.run(:import, Autobuild.tool(:git),
                        '--git-dir', git_dir(package, false),
                        *args, Hash[resolved_env: Hash.new].merge(options))
        end

        # @api private
        #
        # Set a remote up in the repositorie's configuration
        def setup_remote(package, remote_name, repository, push_to = repository)
            run_git_bare(package, 'config', '--replace-all', "remote.#{remote_name}.url", repository)
            run_git_bare(package, 'config', '--replace-all', "remote.#{remote_name}.pushurl", push_to || repository)
            run_git_bare(package, 'config', '--replace-all', "remote.#{remote_name}.fetch",  "+refs/heads/*:refs/remotes/#{remote_name}/*")

            if remote_branch && local_branch
                run_git_bare(package, 'config', '--replace-all', "remote.#{remote_name}.push",  "refs/heads/#{local_branch}:refs/heads/#{remote_branch}")
            else
                run_git_bare(package, 'config', '--replace-all', "remote.#{remote_name}.push",  "refs/heads/*:refs/heads/*")
            end
        end

        # Enumerates the remotes that this importer would set up on the
        # repository
        #
        # @yieldparam [String] remote_name the remote name
        # @yieldparam [String] url the remote URL
        # @yieldparam [String] push_to the remote push-to URL
        def each_configured_remote
            ([['autobuild', repository, push_to]] + additional_remotes).each do |args|
                yield(args[0], args[1], args[2] || args[1])
            end
        end

        # @api private
        #
        # Updates the git repository's configuration for the target remote
        def update_remotes_configuration(package)
            each_configured_remote do |*args|
                setup_remote(package, *args)
            end

            if local_branch
                run_git_bare(package, 'config', '--replace-all', "branch.#{local_branch}.remote",  remote_name)
                run_git_bare(package, 'config', '--replace-all', "branch.#{local_branch}.merge", "refs/heads/#{local_branch}")
            end
        end

        # Resolve a commit ref to a tag or commit ID
        def describe_rev(package, rev)
            tag = run_git_bare(package, 'describe', '--tags', '--exact-match', rev).first.strip
            return true, tag.encode('UTF-8')
        rescue Autobuild::SubcommandFailed
            commit = rev_parse(package, rev)
            return false, commit.encode('UTF-8')
        end

        # Enumerates the ref that are present on the remote
        #
        # @yieldparam [String] ref_name the ref name
        # @yieldparam [String] commit_id the ref's commit ID
        def each_remote_ref(package)
            return enum_for(__method__, package) if !block_given?
            run_git_bare(package, 'ls-remote', repository).each do |line|
                commit_id, ref_name = line.split(/\s+/)
                if ref_name !~ /\^/
                    yield(ref_name, commit_id)
                end
            end
        end

        # @api private
        #
        # Fetches updates from the remote repository. Returns the remote commit
        # ID on success, nil on failure. Expects the current directory to be the
        # package's source directory.
        def fetch_remote(package, options = Hash.new)
            validate_importdir(package)
            if !options[:refspec]
                raise ArgumentError, "required argument 'refspec' not given"
            end

            git_dir = git_dir(package, false)

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
            refspec = Array(options[:refspec])
            tag_arg = ['--tags'] if tag
            run_git_bare(package, 'fetch', repository, *tag_arg, *refspec, retry: true)

            update_remotes_configuration(package)

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
            if (options[:refspec] == tag) && commit_id
                run_git_bare(package, 'update-ref', "-m", "updated by autobuild", "refs/remotes/#{remote_name}/#{remote_branch}", commit_id)
            end

            commit_id
        end

        # @api private
        #
        # Tests whether the package's working copy has uncommitted changes
        #
        # @param [Package] package
        # @param [Boolean] with_untracked_files whether untracked files are
        #   considered uncommitted changes
        def self.has_uncommitted_changes?(package, with_untracked_files = false)
            status = run_git(package, 'status', '--porcelain').map(&:strip)
            if with_untracked_files
                !status.empty?
            else
                status.any? { |l| l[0, 2] !~ /^\?\?|^  / }
            end
        end

        # @api private
        #
        # Returns the commit ID of what we should consider being the remote
        # commit
        #
        # @param [Package] package
        # @options options [Boolean] only_local if true, no remote access should be
        #   performed, in which case the current known state of the remote will be
        #   used. If false, we access the remote repository to fetch the actual
        #   commit ID
        # @options options [Array] refspec list of refs to fetch. Only the first
        #   one is returned by this method
        # @return [String] the commit ID as a string
        def current_remote_commit(package, options = Hash.new)
            if !options.kind_of?(Hash)
                options = Hash[only_local: options]
            end
            only_local = options.delete(:only_local)


            if only_local
                refspec = options[:refspec] ||
                    ("refs/tags/#{tag}" if tag) ||
                    "refs/remotes/#{remote_name}/#{remote_branch}"
                refspec = Array(refspec).first
                begin
                    run_git_bare(package, 'show-ref', '-s', refspec).first.strip
                rescue SubcommandFailed
                    raise PackageException.new(package, "import"), "cannot resolve #{refspec}"
                end
            else
                refspec = options[:refspec] ||
                    ("refs/tags/#{tag}" if tag) ||
                    "refs/heads/#{remote_branch}"
                begin fetch_remote(package, refspec: refspec)
                rescue Exception => e
                    return fallback(e, package, :status, package, only_local)
                end
            end
        end

        # Returns a {Status} object that represents the status of this package
        # w.r.t. the expected remote repository and branch
        def status(package, options = Hash.new)
            if !options.kind_of?(Hash)
                only_local = options
            else
                only_local = options.fetch(:only_local, false)
            end

            validate_importdir(package)
            remote_commit = current_remote_commit(package, only_local)
            status = merge_status(package, remote_commit)
            status.uncommitted_code = self.class.has_uncommitted_changes?(package)
            if current_branch = self.current_branch(package)
                if current_branch != "refs/heads/#{local_branch}"
                    status.unexpected_working_copy_state << "working copy is on branch #{current_branch}, the autoproj configuration expected it to be on #{local_branch}"
                end
            else
                status.unexpected_working_copy_state << "working copy is on a detached HEAD"
            end
            status
        end

        def has_commit?(package, commit_id)
            run_git_bare(package, 'rev-parse', '-q', '--verify', "#{commit_id}^{commit}")
            true
        rescue SubcommandFailed => e
            if e.status == 1
                false
            else raise
            end
        end

        def has_branch?(package, branch_name)
            run_git_bare(package, 'show-ref', '-q', '--verify', "refs/heads/#{branch_name}")
            true
        rescue SubcommandFailed => e
            if e.status == 1
                false
            else raise
            end
        end

        def has_local_branch?(package)
            has_branch?(package, local_branch)
        end

        def detached_head?(package)
            current_branch(package).nil?
        end

        # Returns the branch HEAD is pointing to
        #
        # @return [String,nil] the full ref HEAD is pointing to (i.e.
        #   refs/heads/master), or nil if HEAD is detached
        # @raises SubcommandFailed if git failed
        def current_branch(package)
            run_git_bare(package, 'symbolic-ref', 'HEAD', '-q').first.strip
        rescue SubcommandFailed => e
            if e.status == 1
                return
            else raise
            end
        end

        # Checks if the current branch is the target branch. Expects that the
        # current directory is the package's directory
        def on_local_branch?(package)
            if current_branch = self.current_branch(package)
                current_branch == "refs/heads/#{local_branch}"
            end
        end

        # @deprecated use on_local_branch? instead
        def on_target_branch?(package)
            on_local_branch?(package)
        end

        # A {Importer::Status} object extended to store more git-specific
        # information
        #
        # This is the value returned by {Git#status}
        class Status < Importer::Status
            attr_reader :fetch_commit
            attr_reader :head_commit
            attr_reader :common_commit

            def initialize(package, status, remote_commit, local_commit, common_commit)
                super()
                @status        = status
                @fetch_commit  = fetch_commit
                @head_commit   = head_commit
                @common_commit = common_commit

                if remote_commit != common_commit
                    @remote_commits = log(package, common_commit, remote_commit)
                end
                if local_commit != common_commit
                    @local_commits = log(package, common_commit, local_commit)
                end
            end

            def needs_update?
                status == Status::NEEDS_MERGE || status == Status::SIMPLE_UPDATE
            end

            def log(package, from, to)
                log = package.importer.run_git_bare(package, 'log', '--encoding=UTF-8', "--pretty=format:%h %cr %cn %s", "#{from}..#{to}")
                log.map do |line|
                    line.strip.encode
                end
            end
        end

        # @api private
        #
        # Resolves a revision into a commit ID
        #
        # @param [Package] package
        # @param [String] name the revspec that is to be resolved
        # @param [String] objecT_type the type of git object we want to resolve to
        # @return [String] the commit ID
        # @raise [PackageException] if name cannot be found
        def rev_parse(package, name, object_type = "commit")
            if object_type
                name = "#{name}^{#{object_type}}"
            end
            run_git_bare(package, 'rev-parse', '-q', '--verify', name).first
        rescue Autobuild::SubcommandFailed
            raise PackageException.new(package, 'import'), "failed to resolve #{name}. Are you sure this commit, branch or tag exists ?"
        end

        # Returns the file's conents at a certain commit 
        #
        # @param [Package] package
        # @param [String] commit
        # @param [String] path
        # @return [String]
        def show(package, commit, path)
            run_git_bare(package, 'show', "#{commit}:#{path}").join("\n")
        rescue Autobuild::SubcommandFailed
            raise PackageException.new(package, 'import'), "failed to either resolve commit #{commit} or file #{path}"
        end

        # Tests whether a commit is already present in a given history
        #
        # @param [Package] the package we are working on
        # @param [String] rev what we want to verify the presence of
        # @param [String] reference the reference commit. The method tests that
        #   'commit' is present in the history of 'reference'
        #
        # @return [Boolean]
        def commit_present_in?(package, rev, reference)
            commit = rev_parse(package, rev)
            begin
                merge_base = run_git_bare(package, 'merge-base', commit, reference).first
                merge_base == commit
                
            rescue Exception
                raise PackageException.new(package, 'import'), "failed to find the merge-base between #{rev} and #{reference}. Are you sure these commits exist ?"
            end
        end

        # Finds a remote reference that contains a commit
        #
        # It will favor the configured {#remote_branch} if it matches
        #
        # @param [Autobuild::Package] package the package we are working on
        # @param [String] commit_id the commit ID (can be a rev)
        # @return [String] a remote ref
        # @raise [PackageException] if there is no such commit on the remote
        def describe_commit_on_remote(package, rev = 'HEAD', options = Hash.new)
            rev = rev.to_str
            options = Kernel.validate_options options,
                tags: true

            commit_id = rev_parse(package, rev)

            remote_refs = Hash[*each_remote_ref(package).to_a.flatten]
            remote_branch_ref = "refs/heads/#{remote_branch}"
            remote_branch_id = remote_refs.delete(remote_branch_ref)
            begin
                if commit_present_in?(package, commit_id, remote_branch_id)
                    return remote_branch
                end
            rescue PackageException # We have to fetch. Fetch all branches at once
                fetch_remote(package, refspec: [remote_branch_ref, *remote_refs.keys])
                if commit_present_in?(package, commit_id, remote_branch_id)
                    return remote_branch
                end
            end

            if !options[:tags]
                remote_refs.delete_if { |r| r =~ /^refs\/tags\// }
            end

            # Prefer tags, then heads, then the rest (e.g. github pull requests)
            remote_refs = remote_refs.sort_by do |rev_name, rev_id|
                case rev_name
                when /^refs\/tags\// then 0
                when /^refs\/heads\// then 1
                else 2
                end
            end

            remote_refs.delete_if do |rev_name, rev_id|
                begin
                    if commit_present_in?(package, commit_id, rev_id)
                        return rev_name
                    end
                    true
                rescue PackageException
                    false
                end
            end

            if !remote_refs.empty?
                fetch_remote(package, refspec: remote_refs.map(&:first))
                remote_refs.each do |rev_name, rev_id|
                    if commit_present_in?(package, commit_id, rev_id)
                        return rev_name
                    end
                end
            end

            raise PackageException.new(package), "current HEAD (#{commit_id}) does not seem to be present on the remote"
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
            begin
                common_commit = run_git_bare(package, 'merge-base', reference_commit, fetch_commit).first.strip
            rescue Exception
                raise PackageException.new(package, 'import'), "failed to find the merge-base between #{reference_commit} and #{fetch_commit}. Are you sure these commits exist ?"
            end
            remote_commit = rev_parse(package, fetch_commit)
            head_commit   = rev_parse(package, reference_commit)

            status = if common_commit != remote_commit
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

            Status.new(package, status, fetch_commit, head_commit, common_commit)
        end

        # @api private
        #
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

            if !(current_alternates.sort - alternates.sort).empty?
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

        # @api private
        #
        # Safely resets the current branch to a given commit
        #
        # This method safely resets the current branch to a given commit,
        # not requiring a clean working copy (i.e. it can handle local changes).
        #
        # It verifies that the current HEAD will not be lost by the operation,
        # either because it is included in the target commit or because it is
        # present remotely
        #
        # @param [Package] package the package we handle
        # @param [String] target_commit the commit we want to reset HEAD to
        # @param [String] fetch_commit the state of the remote branch. This is
        #   used to avoid losing commits if HEAD is not included in
        #   target_commit
        # @option options [Boolean] force (false) bypasses checks that verify
        #   that some commits won't be lost by resetting
        def reset_head_to_commit(package, target_commit, fetch_commit, options = Hash.new)
            current_head     = rev_parse(package, 'HEAD')
            head_to_target   = merge_status(package, target_commit, current_head)
            status_to_target = head_to_target.status

            if status_to_target == Status::UP_TO_DATE
                return
            elsif status_to_target == Status::SIMPLE_UPDATE
                run_git(package, 'merge', target_commit)
            elsif !options[:force]
                # Check whether the current HEAD is present on the remote
                # repository. We'll refuse resetting if there are uncommitted
                # changes
                if !commit_present_in?(package, current_head, fetch_commit)
                    raise ImporterCannotReset.new(package, 'import'), "branch #{local_branch} of #{package.name} contains commits that do not seem to be present on the branch #{remote_branch} of the remote repository. I can't go on as it could make you loose some stuff. Update the remote branch in your overrides, push your changes or reset to the remote commit manually before trying again"
                end
            end

            package.message "  %%s: resetting branch %s to %s" % [local_branch, target_commit.to_s]
            # I don't use a reset --hard here as it would add even more
            # restrictions on when we can do the operation (as we would refuse
            # doing it if there are local changes). The checkout creates a
            # detached HEAD, but makes sure that applying uncommitted changes is
            # fine (it would abort otherwise). The rest then updates HEAD and
            # the local_branch ref to match the required target commit
            resolved_target_commit = rev_parse(package, "#{target_commit}^{commit}")
            begin
                run_git(package, 'checkout', target_commit)
                run_git(package, 'update-ref', "refs/heads/#{local_branch}", resolved_target_commit)
                run_git(package, 'symbolic-ref', "HEAD", "refs/heads/#{local_branch}")
            rescue ::Exception
                run_git(package, 'symbolic-ref', "HEAD", target_commit)
                run_git(package, 'update-ref', "refs/heads/#{local_branch}", current_head)
                run_git(package, 'checkout', local_branch)
                raise
            end
        end

        # @option (see Package#update)
        def update(package, options = Hash.new)
            validate_importdir(package)
            only_local = options.fetch(:only_local, false)
            reset = options.fetch(:reset, false)
            
            # This is really really a hack to workaround how broken the
            # importdir thing is
            if package.importdir == package.srcdir
                update_alternates(package)
            end

            pinned_state =
                if commit then commit
                elsif tag then "refs/tags/#{tag}"
                end

            if pinned_state
                if !has_commit?(package, pinned_state)
                    fetch_commit = current_remote_commit(
                        package,
                        only_local: only_local,
                        refspec: [remote_branch, tag])
                end
                target_commit = pinned_state = rev_parse(package, pinned_state)
            else
                target_commit = fetch_commit  =
                    current_remote_commit(package, only_local: only_local)
            end

            # If we are tracking a commit/tag, just check it out and return
            if !has_local_branch?(package)
                package.message "%%s: checking out branch %s" % [local_branch]
                run_git(package, 'checkout', '-b', local_branch, target_commit)
                return
            end

            if !on_local_branch?(package)
                package.message "%%s: switching to branch %s" % [local_branch]
                run_git(package, 'checkout', local_branch)
            end

            # Check whether we are already at the requested state
            if pinned_state
                current_head = rev_parse(package, 'HEAD')
                if reset
                    if current_head == pinned_state
                        return
                    end
                elsif commit_present_in?(package, pinned_state, current_head)
                    return
                elsif merge_if_simple(package, pinned_state)
                    return
                end
            end

            fetch_commit ||= current_remote_commit(
                package, only_local: only_local, refspec: [remote_branch, tag])
            if reset
                reset_head_to_commit(package, target_commit, fetch_commit, force: (reset == :force))
            else
                merge_if_simple(package, target_commit)
            end
        end

        # @api private
        def merge_if_simple(package, target_commit)
            status = merge_status(package, target_commit)
            if status.needs_update?
                if !merge? && status.status == Status::NEEDS_MERGE
                    raise PackageException.new(package, 'import'), "the local branch '#{local_branch}' and the remote branch #{branch} of #{package.name} have diverged, and I therefore refuse to update automatically. Go into #{package.importdir} and either reset the local branch or merge the remote changes"
                end
                run_git(package, 'merge', target_commit)
                true
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

        def checkout(package, options = Hash.new)
            base_dir = File.expand_path('..', package.importdir)
            if !File.directory?(base_dir)
                FileUtils.mkdir_p base_dir
            end

            clone_options = Array.new
            if with_submodules?
                clone_options << '--recurse-submodules'
            end
            each_alternate_path(package) do |path|
                clone_options << '--reference' << path
            end
            package.run(:import,
                Autobuild.tool('git'), 'clone', '-o', remote_name, *clone_options, repository, package.importdir, retry: true)

            update_remotes_configuration(package)
            update(package, only_local: true, reset: true)
        end

        # Changes the repository this importer is pointing to
        def relocate(repository, options = Hash.new)
            options = Hash[options.map { |k, v| [k.to_sym, v] }]

            @push_to = options[:push_to] || @push_to
            local_branch  = options[:local_branch]  || options[:branch] || self.local_branch || 'master'
            remote_branch = options[:remote_branch] || options[:branch] || self.remote_branch || 'master'
            @branch = @local_branch = @remote_branch = nil
            if local_branch == remote_branch
                @branch = local_branch
            else
                @local_branch = local_branch
                @remote_branch = remote_branch
            end
            @tag    = options[:tag] || @tag
            @commit = options[:commit] || @commit

            @repository = repository.to_str
            @repository_id = options[:repository_id] ||
                "git:#{@repository}"
            @source_id = options[:source_id] ||
                "#{@repository_id} branch=#{remote_branch} tag=#{self.tag} commit=#{self.commit}"
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
        def self.vcs_definition_for(path, remote_name = 'autobuild')
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

        def declare_alternate_repository(name, repository, options = Hash.new)
            if !name
                raise ArgumentError, "cannot declare alternate repository #{repository} without a name"
            end
            additional_remotes << [name, repository, options[:push_to] || repository]
        end
    end

    # Creates a git importer which gets the source for the given repository and branch
    # URL +source+.
    def self.git(repository, branch = nil, options = {})
        Git.new(repository, branch, options)
    end
end

