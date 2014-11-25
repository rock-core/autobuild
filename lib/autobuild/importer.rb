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

        # An array of strings that represent commits that are in the remote
        # repository and not in this one (would be merged by an update)
        attr_accessor :remote_commits
        # An array of strings that represent commits that are in the local
        # repository and not in the remote one (would be pushed by an update)
        attr_accessor :local_commits

        def initialize
            @status = -1
            @uncommitted_code = false
            @remote_commits = Array.new
            @local_commits  = Array.new
        end
    end

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
        @source_id = options[:source_id] || @repository_id
    end

    # Returns a string that identifies the remote repository uniquely
    #
    # This can be used to check whether two importers are pointing to the same
    # repository, regardless of e.g. the access protocol used.  For instance,
    # two git importers that point to the same repository but different branches
    # would have the same repository_id but different source_id
    #
    # @see source_id
    attr_reader :repository_id

    # Returns a string that identifies the remote source uniquely
    #
    # This can be used to check whether two importers are pointing to the same
    # code base inside the same repository. For instance, two git importers that
    # point to the same repository but different branches would have the same
    # repository_id but different source_id
    #
    # @see repository_id
    attr_reader :source_id

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

    def perform_update(package,only_local=false)
        cur_patches    = currently_applied_patches(package)
        needed_patches = self.patches
        if cur_patches.map(&:last) != needed_patches.map(&:last)
            patch(package, [])
        end

        retry_count = 0
        package.progress_start "updating %s"
        begin
            update(package,only_local)
        rescue Interrupt
            raise
        rescue ::Exception => original_error
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
                package.message "update failed and some patches are applied, retrying after removing all patches first"
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

    def perform_checkout(package)
        package.progress_start "checking out %s", :done_message => 'checked out %s' do
            retry_count = 0
            begin
                checkout(package)
            rescue Interrupt
                raise
            rescue ::Exception => original_error
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

    # Performs the import of +package+
    def import(package,only_local = false)
        importdir = package.importdir
        if File.directory?(importdir)
            package.isolate_errors(false) do
                if package.update?
                    perform_update(package,only_local)
                else
                    if Autobuild.verbose
                        package.message "%s: not updating"
                    end
                    return
                end
            end

        elsif File.exists?(importdir)
            raise ConfigException.new(package, 'import'), "#{importdir} exists but is not a directory"
        else
            perform_checkout(package)
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

    private

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
        if File.exists?(patches_file)
            return parse_patch_list(package, patches_file)
        end

        patches_file = File.join(package.importdir, "patches-autobuild-stamp")
        if File.exists?(patches_file)
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

            patches.to_a.each do |p, level, content|
                apply(package, p, level)
                cur_patches << [p, level, content]
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

