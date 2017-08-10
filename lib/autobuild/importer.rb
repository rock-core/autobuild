require 'autobuild/config'
require 'autobuild/exceptions'

# This class is the base class for objects that are used to get the source from
# various RCS into the package source directory. A list of patches to apply
# after the import can be given in the +:patches+ option.
module Autobuild
class Importer
    # call-seq:
    #   Autobuild::Importer.fallback { |package, importer| ... }
    #
    # If called, registers the given block as a fallback mechanism for failing
    # imports.
    #
    # Fallbacks are tried in reverse order with the failing importer object as
    # argument. The first valid importer object that has been returned will be
    # used instead.
    #
    # It is the responsibility of the fallback handler to make sure that it does
    # not do infinite recursions and stuff like that.
    def self.fallback(&block)
        @fallback_handlers.unshift(block)
    end

    class << self
        # The set of handlers registered by Importer.fallback
        attr_reader :fallback_handlers
    end

    @fallback_handlers = Array.new

    # Instances of the Importer::Status class represent the status of a current
    # checkout w.r.t. the remote repository.
    class Status
        # Remote and local are at the same point
        UP_TO_DATE    = 0
        # Local contains all data that remote has, but has new commits
        ADVANCED      = 1
        # Next update will require a merge
        NEEDS_MERGE   = 2
        # Next update will be simple (no merge)
        SIMPLE_UPDATE = 3

        # The update status
        attr_accessor :status
        # True if there is code in the working copy that is not committed
        attr_accessor :uncommitted_code
        # A list of messages describing differences between the local working
        # copy and its expected state
        #
        # On git, it would for instance mention that currently checked out
        # branch is not the one autoproj expects
        #
        # @return [Array<String>]
        attr_reader :unexpected_working_copy_state

        # An array of strings that represent commits that are in the remote
        # repository and not in this one (would be merged by an update)
        attr_accessor :remote_commits
        # An array of strings that represent commits that are in the local
        # repository and not in the remote one (would be pushed by an update)
        attr_accessor :local_commits

        def initialize(status = -1)
            @status = status
            @unexpected_working_copy_state = Array.new
            @uncommitted_code = false
            @remote_commits = Array.new
            @local_commits  = Array.new
        end
    end

    # The cache directories for the given importer type.
    #
    # This is used by some importers to save disk space and/or avoid downloading
    # the same things over and over again
    #
    # The default global cache directory is initialized from the
    # AUTOBUILD_CACHE_DIR environment variable. Per-importer cache directories
    # can be overriden by setting AUTOBUILD_{TYPE}_CACHE_DIR (e.g.
    # AUTOBUILD_GIT_CACHE_DIR)
    #
    # The following importers use caches:
    # - the archive importer saves downloaded files in the cache. They are
    #   saved under an archives/ subdirectory of the default cache if set, or to
    #   the value of AUTOBUILD_ARCHIVES_CACHE_DIR
    # - the git importer uses the cache directories as alternates for the git
    #   checkouts
    #
    # @param [String] type the importer type. If set, it Given a root cache
    #   directory X, and importer specific cache is setup as a subdirectory of X
    #   with e.g. X/git or X/archives. The subdirectory name is defined by this
    #   argument
    # @return [nil,Array<String>]
    #
    # @see .set_cache_dirs .default_cache_dirs .default_cache_dirs=
    def self.cache_dirs(type)
        if @cache_dirs[type] || (env = ENV["AUTOBUILD_#{type.upcase}_CACHE_DIR"])
            @cache_dirs[type] ||= env.split(":")
        elsif dirs = default_cache_dirs
            dirs.map { |d| File.join(d, type) }
        end
    end

    # Returns the default cache directory if there is one
    #
    # @return [Array<String>,nil]
    # @see .cache_dirs
    def self.default_cache_dirs
        if @default_cache_dirs ||= ENV['AUTOBUILD_CACHE_DIR']
            [@default_cache_dirs]
        end
    end

    # Sets the cache directory for a given importer type
    #
    # @param [String] type the importer type
    # @param [String] dir the cache directory
    # @see .cache_dirs
    def self.set_cache_dirs(type, *dirs)
        @cache_dirs[type] = dirs
    end

    # Sets the default cache directory
    #
    # @param [Array<String>,String] the directories
    # @see .cache_dirs
    def self.default_cache_dirs=(dirs)
        @default_cache_dirs = Array(dirs)
    end

    # Unset all cache directories
    def self.unset_cache_dirs
        @cache_dirs = Hash.new
        @default_cache_dirs = nil
    end

    unset_cache_dirs

    # @return [Hash] the original option hash as given to #initialize
    attr_reader :options

    # Creates a new Importer object. The options known to Importer are:
    # [:patches] a list of patch to apply after import
    #
    # More options are specific to each importer type.
    def initialize(options)
        @options = options.dup
        @options[:retry_count] = Integer(@options[:retry_count] || 0)
        @repository_id = options[:repository_id] || "#{self.class.name}:#{object_id}"
        @interactive = options[:interactive]
        @source_id = options[:source_id] || @repository_id
        @post_hooks = Array.new
    end

    # Returns a string that identifies the remote repository uniquely
    #
    # This can be used to check whether two importers are pointing to the same
    # repository, regardless of e.g. the access protocol used.  For instance,
    # two git importers that point to the same repository but different branches
    # would have the same repository_id but different source_id
    #
    # @return [String]
    # @see source_id
    attr_reader :repository_id

    # Returns a string that identifies the remote source uniquely
    #
    # This can be used to check whether two importers are pointing to the same
    # code base inside the same repository. For instance, two git importers that
    # point to the same repository but different branches would have the same
    # repository_id but different source_id
    #
    # @return [String]
    # @see repository_id
    attr_reader :source_id

    # Whether this importer will need interaction with the user, for instance to
    # give credentials
    def interactive?; !!@interactive end

    # Changes whether this importer is interactive or not
    def interactive=(value)
        @interactive = !!value
    end

    # The number of times update / checkout should be retried before giving up.
    # The default is 0 (do not retry)
    #
    # Set either with #retry_count= or by setting the :retry_count option when
    # constructing this importer
    def retry_count
        @options[:retry_count] || 0
    end

    # Sets the number of times update / checkout should be retried before giving
    # up. 0 (the default) disables retrying.
    #
    # See also #retry_count
    def retry_count=(count)
        @options[:retry_count] = Integer(count)
    end

    def patches
        patches =
            if @options[:patches].respond_to?(:to_ary)
                @options[:patches]
            elsif !@options[:patches]
                []
            else
                [[@options[:patches], 0]]
            end

        if patches.size == 2 && patches[0].respond_to?(:to_str) && patches[1].respond_to?(:to_int)
            patches = [patches]
        else
            patches = patches.map do |obj|
                if obj.respond_to?(:to_str)
                    [obj, 0]
                elsif obj.respond_to?(:to_ary)
                    obj
                else
                    raise Arguments, "wrong patch specification #{obj.inspect}"
                    obj
                end
            end
        end
        patches.map do |path, level|
            [path, level, File.read(path)]
        end
    end

    def update_retry_count(original_error, retry_count)
        if !original_error.respond_to?(:retry?) ||
            !original_error.retry?
            return
        end

        retry_count += 1
        if retry_count <= self.retry_count
            retry_count
        end
    end

    # A list of hooks that are called after a successful checkout or update
    #
    # They are added either at the instance level with {#add_post_hook} or
    # globally for all importers of a given type with {Importer.add_post_hook}
    attr_reader :post_hooks

    # Define a post-import hook for all instances of this class
    #
    # @yieldparam [Importer] importer the importer that finished
    # @yieldparam [Package] package the package we're acting on
    # @see Importer#add_post_hook
    def self.add_post_hook(&hook)
        @post_hooks ||= Array.new
        @post_hooks << hook
    end

    # Enumerate the post-import hooks defined for all instances of this class
    def self.each_post_hook(&hook)
        (@post_hooks ||= Array.new).each(&hook)
    end

    # @api private
    #
    # Call the post-import hooks added with {#add_post_hook}
    def execute_post_hooks(package)
        each_post_hook.each do |block|
            block.call(self, package)
        end
    end

    # Add a block that should be called when the import has successfully
    # finished
    #
    # @yieldparam [Importer] importer the importer that finished
    # @yieldparam [Package] package the package we're acting on
    # @see Importer.add_post_hook
    def add_post_hook(&hook)
        post_hooks << hook
    end

    # Enumerate the post-import hooks for this importer
    def each_post_hook(&hook)
        return enum_for(__method__) if !block_given?

        self.class.each_post_hook(&hook)
        post_hooks.each(&hook)
    end

    def perform_update(package,only_local=false)
        cur_patches    = currently_applied_patches(package)
        needed_patches = self.patches
        if cur_patches.map(&:last) != needed_patches.map(&:last)
            patch(package, [])
        end

        last_error = nil
        retry_count = 0
        package.progress_start "updating %s"
        begin
            update(package,only_local)
            execute_post_hooks(package)
        rescue Interrupt
            if last_error
                raise last_error
            else raise
            end
        rescue ::Exception => original_error
            last_error = original_error
            # If the package is patched, it might be that the update
            # failed because we needed to unpatch first. Try it out
            #
            # This assumes that importing data with conflict will
            # make the import fail, but not make the patch
            # un-appliable. Importers that do not follow this rule
            # will have to unpatch by themselves.
            cur_patches = currently_applied_patches(package)
            if !cur_patches.empty?
                package.progress_done
                package.message "update failed and some patches are applied, removing all patches and retrying"
                begin
                    patch(package, [])
                    return perform_update(package,only_local)
                rescue Interrupt
                    raise
                rescue ::Exception
                    raise original_error
                end
            end

            retry_count = update_retry_count(original_error, retry_count)
            raise if !retry_count
            package.message "update failed in #{package.importdir}, retrying (#{retry_count}/#{self.retry_count})"
            retry
        ensure
            package.progress_done "updated %s"
        end

        patch(package)
        package.updated = true
    rescue Interrupt
        raise
    rescue Autobuild::Exception => e
        fallback(e, package, :import, package)
    end

    def perform_checkout(package, options = Hash.new)
        last_error = nil
        package.progress_start "checking out %s", :done_message => 'checked out %s' do
            retry_count = 0
            begin
                checkout(package, options)
                execute_post_hooks(package)
            rescue Interrupt
                if last_error then raise last_error
                else raise
                end
            rescue ::Exception => original_error
                last_error = original_error
                retry_count = update_retry_count(original_error, retry_count)
                if !retry_count
                    raise
                end
                package.message "checkout of %s failed, deleting the source directory #{package.importdir} and retrying (#{retry_count}/#{self.retry_count})"
                FileUtils.rm_rf package.importdir
                retry
            end
        end

        patch(package)
        package.updated = true
    rescue Interrupt
        raise
    rescue ::Exception
        package.message "checkout of %s failed, deleting the source directory #{package.importdir}"
        FileUtils.rm_rf package.importdir
        raise
    rescue Autobuild::Exception => e
        FileUtils.rm_rf package.importdir
        fallback(e, package, :import, package)
    end

    # Imports the given package
    #
    # The importer will checkout or update code in package.importdir. No update
    # will be done if {update?} returns false.
    #
    # @raises ConfigException if package.importdir exists and is not a directory
    #
    # @option options [Boolean] :checkout_only (false) if true, the importer
    #   will not update an already checked-out package.
    # @option options [Boolean] :only_local (false) if true, will only perform
    #   actions that do not require network access. Importers that do not
    #   support this mode will simply do nothing
    # @option options [Boolean] :reset (false) if true, the importer's
    #   configuration is interpreted as a hard state in which it should put the
    #   working copy. Otherwise, it tries to update the local repository with
    #   the remote information. For instance, a git importer for which a commit
    #   ID is given will, in this mode, reset the repository to the requested ID
    #   (if that does not involve losing commits). Otherwise, it will only
    #   ensure that the requested commit ID is present in the current HEAD.
    def import(package, options = Hash.new)
        # Backward compatibility
        if !options.kind_of?(Hash)
            options = !!options
            Autoproj.warn "calling #import with a boolean as second argument is deprecated, switch to the named argument interface instead"
            Autoproj.warn "   e.g. call import(package, only_local: #{options})"
            Autoproj.warn "   #{caller(1).first}"
            options = Hash[only_local: !!options]
        end

        options = Kernel.validate_options options,
            only_local: false,
            reset: false,
            checkout_only: false,
            ignore_errors: false,
            allow_interactive: true
        ignore_errors = options.delete(:ignore_errors)

        importdir = package.importdir
        if File.directory?(importdir)
            package.isolate_errors(mark_as_failed: false, ignore_errors: ignore_errors) do
                if !options[:checkout_only] && package.update?
                    perform_update(package, options)
                else
                    if Autobuild.verbose
                        package.message "%s: not updating"
                    end
                    return
                end
            end

        elsif File.exist?(importdir)
            raise ConfigException.new(package, 'import'), "#{importdir} exists but is not a directory"
        else
            package.isolate_errors(mark_as_failed: true, ignore_errors: ignore_errors) do
                perform_checkout(package, allow_interactive: options[:allow_interactive])
            end
        end
    end

    # Tries to find a fallback importer because of the given error.
    def fallback(error, package, *args, &block)
        Importer.fallback_handlers.each do |handler|
            fallback_importer = handler.call(package, self)
            if fallback_importer.kind_of?(Importer)
                begin
                    return fallback_importer.send(*args, &block)
                rescue Exception
                    raise error
                end
            end
        end
        raise error
    end

    def patchdir(package)
        File.join(package.importdir, ".autobuild-patches")
    end
    
    # We assume that package.importdir already exists (checkout is supposed to
    # have been called)
    def patchlist(package)
        File.join(patchdir(package), "list")
    end

    def call_patch(package, reverse, file, patch_level)
        package.run(:patch, Autobuild.tool('patch'),
                    "-p#{patch_level}", (reverse ? '-R' : nil), '--forward', input: file,
                    working_directory: package.importdir)
    end

    def apply(package, path, patch_level = 0);   call_patch(package, false, path, patch_level) end
    def unapply(package, path, patch_level = 0); call_patch(package, true, path, patch_level)   end

    def parse_patch_list(package, patches_file)
        File.readlines(patches_file).map do |line| 
            line = line.rstrip
            if line =~ /^(.*)\s+(\d+)$/
                path = File.expand_path($1, package.srcdir)
                level = Integer($2)
            else
                path = File.expand_path(line, package.srcdir)
                level = 0
            end
            [path, level, File.read(path)]
        end
    end

    def currently_applied_patches(package)
        patches_file = patchlist(package)
        if File.exist?(patches_file)
            return parse_patch_list(package, patches_file)
        end

        patches_file = File.join(package.importdir, "patches-autobuild-stamp")
        if File.exist?(patches_file)
            cur_patches = parse_patch_list(package, patches_file)
            save_patch_state(package, cur_patches)
            FileUtils.rm_f patches_file
            return currently_applied_patches(package)
        end

        return Array.new
    end

    def patch(package, patches = self.patches)
        # Get the list of already applied patches
        cur_patches = currently_applied_patches(package)

        cur_patches_state = cur_patches.map { |_, level, content| [level, content] }
        patches_state     = patches.map { |_, level, content| [level, content] }
        if cur_patches_state == patches_state
            return false
        end

        # Do not be smart, remove all already applied patches
        # and then apply the new ones
        begin
            apply_count = (patches - cur_patches).size
            unapply_count = (cur_patches - patches).size
            if apply_count > 0 && unapply_count > 0
                package.message "patching %s: applying #{apply_count} and unapplying #{unapply_count} patch(es)"
            elsif apply_count > 0
                package.message "patching %s: applying #{apply_count} patch(es)"
            elsif unapply_count > 0
                package.message "patching %s: unapplying #{unapply_count} patch(es)"
            end

            while p = cur_patches.last
                p, level, _ = *p
                unapply(package, p, level)
                cur_patches.pop
            end

            patches.to_a.each do |new_patch, new_patch_level, content|
                apply(package, new_patch, new_patch_level)
                cur_patches << [new_patch, new_patch_level, content]
	    end
        ensure
            save_patch_state(package, cur_patches)
        end

        return true
    end
    
    def save_patch_state(package, cur_patches)
        patch_dir = patchdir(package)
        FileUtils.mkdir_p patch_dir
        cur_patches = cur_patches.each_with_index.map do |(path, level, content), idx|
            path = File.join(patch_dir, idx.to_s)
            File.open(path, 'w') do |patch_io|
                patch_io.write content
            end
            [path, level]
        end
        File.open(patchlist(package), 'w') do |f|
            patch_state = cur_patches.map do |path, level|
                path = Pathname.new(path).relative_path_from( Pathname.new(package.srcdir) ).to_s
                "#{path} #{level}"
            end
            f.write(patch_state.join("\n"))
        end
    end

    def supports_relocation?; false end
end
end

