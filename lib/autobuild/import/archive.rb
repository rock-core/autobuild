require 'autobuild/importer'
require 'open-uri'
require 'fileutils'

module Autobuild
    class ArchiveImporter < Importer
	# The tarball is not compressed
        Plain = 0
	# The tarball is compressed with gzip
        Gzip  = 1
	# The tarball is compressed using bzip
        Bzip  = 2
        # Not a tarball but a zip
        Zip   = 3

        TAR_OPTION = {
            Plain => '',
            Gzip => 'z',
            Bzip => 'j'
        }

	# Known URI schemes for +url+
        VALID_URI_SCHEMES = [ 'file', 'http', 'https', 'ftp' ]

	# Returns the unpack mode from the file name
        def self.filename_to_mode(filename)
            case filename
                when /\.zip$/; Zip
                when /\.tar$/; Plain
                when /\.tar\.gz$|\.tgz$/;  Gzip
                when /\.bz2$/; Bzip
                else
                    raise "unknown file type '#{filename}'"
            end
        end

        def update_cached_file?; @options[:update_cached_file] end

	# Updates the downloaded file in cache only if it is needed
        def update_cache(package)
            do_update = false

            if !File.file?(cachefile)
                do_update = true
            elsif self.update_cached_file?
                cached_size = File.lstat(cachefile).size
                cached_mtime = File.lstat(cachefile).mtime

                size, mtime = nil
                if @url.scheme == "file"
                    size  = File.stat(@url.path).size
                    mtime = File.stat(@url.path).mtime
                else
                    open @url, :content_length_proc => lambda { |size| } do |file| 
                        mtime = file.last_modified
                    end
                end

                if mtime && size
                    do_update = (size != cached_size || mtime > cached_mtime)
                elsif mtime
                    $stderr.puts "WARNING: size is not available for #{@url}, relying on modification time"
                    do_update = (mtime > cached_mtime)
                elsif size
                    $stderr.puts "WARNING: modification time is not available for #{@url}, relying on size"
                    do_update = (size != cached_size)
                else
                    $stderr.puts "WARNING: neither size nor modification time available for #{@url}, will always update"
                    do_update = true
                end
            end

            if do_update
                FileUtils.mkdir_p(cachedir)
                begin
                    Subprocess.run(package, :import, Autobuild.tool('wget'), '-q', '-P', cachedir, @url, '-O', "#{cachefile}.partial")
                rescue Exception
                    FileUtils.rm_f "#{cachefile}.partial"
                    raise
                end
                FileUtils.mv "#{cachefile}.partial", cachefile
                true
            end
        end

	# The source URL
        attr_reader :url
	# The local file (either a downloaded file if +url+ is not local, or +url+ itself)
	attr_reader :cachefile
	# The unpack mode. One of Zip, Bzip, Gzip or Plain
	attr_reader :mode
	# The directory in which remote files are cached
        def cachedir; @options[:cachedir] end
	# The directory contained in the tar file
        #
        # DEPRECATED use #archive_dir instead
	def tardir; @options[:tardir] end
        # The directory contained in the archive. If not set, we assume that it
        # is the same than the source dir
        def archive_dir; @options[:archive_dir] || tardir end

        # Returns a string that identifies the remote repository uniquely
        #
        # This is meant for display purposes
        def repository_id
            url.dup
        end

	# Creates a new importer which downloads +url+ in +cachedir+ and unpacks it. The following options
	# are allowed:
	# [:cachedir] the cache directory. Defaults to "#{Autobuild.prefix}/cache"
        # [:archive_dir] the directory contained in the archive file. If set,
        #       the importer will rename that directory to make it match
        #       Package#srcdir
        # [:no_subdirectory] the archive does not have the custom archive
        #       subdirectory.
        def initialize(url, options)
            @options = options.dup
            if !@options.has_key?(:update_cached_file)
                @options[:update_cached_file] = true
            end
            @options[:cachedir] ||= "#{Autobuild.prefix}/cache"

            @url = URI.parse(url)
            if !VALID_URI_SCHEMES.include?(@url.scheme)
                raise ConfigException, "invalid URL #{@url} (local files must be prefixed with file://)" 
            end

            filename = options[:filename] || File.basename(url).gsub(/\?.*/, '')
            @mode = options[:mode] || ArchiveImporter.filename_to_mode(filename)
            if @url.scheme == 'file'
                @cachefile = @url.path
            else
                @cachefile = File.join(cachedir, filename)
            end
        end

        def update(package) # :nodoc:
            checkout(package) if update_cache(package)
        rescue OpenURI::HTTPError
            raise Autobuild::Exception.new(package.name, :import)
        end

        def checkout(package) # :nodoc:
            update_cache(package)

            base_dir = File.dirname(package.srcdir)

            if mode == Zip
                main_dir = if @options[:no_subdirectory] then package.srcdir
                           else base_dir
                           end

                cmd = [ '-o', cachefile, '-d', main_dir ]
                Subprocess.run(package, :import, Autobuild.tool('unzip'), *cmd)
                
                if archive_dir
                    FileUtils.rm_rf File.join(package.srcdir)
                    FileUtils.mv File.join(base_dir, archive_dir), package.srcdir
                elsif !File.directory?(package.srcdir)
                    raise Autobuild::Exception, "#{cachefile} does not contain directory called #{File.basename(package.srcdir)}. Did you forget to use the :archive_dir option ?"
                end
            else
                FileUtils.mkdir_p package.srcdir
                cmd = ["x#{TAR_OPTION[mode]}f", cachefile, '-C', package.srcdir]
                if !@options[:no_subdirectory]
                    cmd << '--strip-components=1'
                end
                Subprocess.run(package, :import, Autobuild.tool('tar'), *cmd)
            end

        rescue OpenURI::HTTPError
            raise Autobuild::Exception.new(package.name, :import)
        rescue SubcommandFailed
            FileUtils.rm_f cachefile
            raise
        end
    end

    # For backwards compatibility
    TarImporter = ArchiveImporter

    # Creates an importer which downloads a tarball from +source+ and unpacks
    # it. The allowed values in +options+ are described in ArchiveImporter.new.
    def self.archive(source, options = {})
	ArchiveImporter.new(source, options)
    end

    # DEPRECATED. Use Autobuild.archive instead.
    def self.tar(source, options = {})
	ArchiveImporter.new(source, options)
    end
end

