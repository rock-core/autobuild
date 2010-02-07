require 'autobuild/config'
require 'autobuild/exceptions'

# This class is the base class for objects that are used to get the source from
# various RCS into the package source directory. A list of patches to apply
# after the import can be given in the +:patches+ option.
module Autobuild
class Importer
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

    # Creates a new Importer object. The options known to Importer are:
    # [:patches] a list of patch to apply after import
    #
    # More options are specific to each importer type.
    def initialize(options); @options = options end

    def patches
        if @options[:patches].respond_to?(:to_ary)
            @options[:patches]
        elsif !@options[:patches]
            []
        else
            [@options[:patches]]
        end
    end

    # Performs the import of +package+
    def import(package)
        srcdir = package.srcdir
        if File.directory?(srcdir)
            if Autobuild.do_update
		package.progress "updating %s"
                update(package)
                patch(package)
            else
		if Autobuild.verbose
		    puts "  not updating #{package.name}"
		end
                return
            end

        elsif File.exists?(srcdir)
            raise ConfigException, "#{srcdir} exists but is not a directory"
        else
            begin
		package.progress "checking out %s"
                checkout(package)
                patch(package)
            rescue Autobuild::Exception
                FileUtils.rm_rf package.srcdir
                raise
            end
        end
    end

    private
    
    # We assume that package.srcdir already exists (checkout is supposed to
    # have been called)
    def patchlist(package)
        File.join(package.srcdir, "patches-autobuild-stamp")
    end

    def call_patch(package, reverse, file)
        patch = Autobuild.tool('patch')
        Dir.chdir(package.srcdir) do
            Subprocess.run(package, :patch, patch, '-p0', (reverse ? '-R' : nil), "<#{file}")
        end
    end

    def apply(package, path);   call_patch(package, false, path) end
    def unapply(package, path); call_patch(package, true, path)   end

    def patch(package)
        # Get the list of already applied patches
        patches_file = patchlist(package)
        cur_patches =   if !File.exists?(patches_file) then []
                        else
                            File.open(patches_file) do |f| 
                                f.readlines.collect { |path| path.rstrip } 
                            end
                        end

	if !patches.empty?
	    package.progress "patching %s"
	end

        # Do not be smart, remove all already applied patches
        # and then apply the new ones
        begin
            while p = cur_patches.last
                unapply(package, p) 
                cur_patches.pop
            end

            patches.to_a.each do |p| 
                apply(package, p) 
                cur_patches << p
	    end
        ensure
            File.open(patchlist(package), 'w+') do |f|
                f.write(cur_patches.join("\n"))
            end
        end
    end
end
end

