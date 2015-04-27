require 'autobuild/importer'
require 'digest/sha1'
require 'open-uri'
require 'fileutils'

WINDOWS = RbConfig::CONFIG["host_os"] =~%r!(msdos|mswin|djgpp|mingw|[Ww]indows)! 
if WINDOWS 
	require 'net/http' 
	require 'net/https'
	require 'rubygems/package'
	require 'zlib'
end


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

        class << self
            # The directory in which downloaded files are saved
            #
            # It defaults, by order of priority, to the archives/ subdirectory
            # of the environment variable AUTOBUILD_CACHE_DIR (if set), to the
            # AUTOBUILD_ARCHIVES_CACHE_DIR (if set) environment variable and to
            # #{prefix}/cache
            def cachedir
                if @cachedir then @cachedir
                elsif dir = ENV['AUTOBUILD_ARCHIVES_CACHE_DIR']
                    @cachedir = File.expand_path(dir)
                elsif dir = ENV['AUTOBUILD_CACHE_DIR']
                    @cachedir = File.join(File.expand_path(dir), 'archives')
                else
                    @cachedir = "#{Autobuild.prefix}/cache"
                end
            end

            # Sets the directory in which files get cached
            attr_writer :cachedir

            # The timeout (in seconds) used during downloading.
            #
            # With wget, it is the timeout used for DNS resolution, connection and
            # idle time (time without receiving data)
            #
            # It defaults to 10s
            attr_accessor :timeout

            # The number of time we should retry downloading if the underlying tool
            # supports it (wget does).
            #
            # It defaults to 1 as autobuild has its own retry mechanism
            attr_accessor :retries
        end
        @retries = 1
        @timeout = 10
        @cachedir = nil

	# Returns the unpack mode from the file name
        #
        # @return [Integer,nil] either one of the pack constants (Zip, Plain,
        #   ...) or nil if it cannot be inferred
        # @see filename_to_mode
        def self.find_mode_from_filename(filename)
            case filename
            when /\.zip$/; Zip
            when /\.tar$/; Plain
            when /\.tar\.gz$|\.tgz$/;  Gzip
            when /\.bz2$/; Bzip
            end
        end

	# Returns the unpack mode from the file name
        def self.filename_to_mode(filename)
            if mode = find_mode_from_filename(filename)
                mode
            else
                raise "cannot infer the archive type from '#{filename}', use the mode: option"
            end
        end

        # Tells the importer that the checkout should be automatically deleted
        # on update, without asking the user
        # @return [Boolean] true if the archive importer should automatically
        #   delete the current checkout when the archive changed, false
        #   otherwise. The default is to set it to true if the
        #   AUTOBUILD_ARCHIVE_AUTOUPDATE environment variable is set to 1, and
        #   to false in all other cases
        def self.auto_update?
            @auto_update
        end
        @auto_update = (ENV['AUTOBUILD_ARCHIVE_AUTOUPDATE'] == '1')

        def update_cached_file?; @options[:update_cached_file] end

		
	def get_url_on_windows(url, filename)
            uri = URI(url)		

            http = Net::HTTP.new(uri.host,uri.port)
            http.use_ssl = true if uri.port == 443
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE  #Unsure, critical?, Review this
            resp = http.get(uri.request_uri)

            if resp.code == "301" or resp.code == "302"
                get_url_on_windows(resp.header['location'],filename)
            else
                if resp.message != 'OK'
                    raise "Could not get File from url \"#{url}\", got response #{resp.message} (#{resp.code})"
                end
                open(filename, "wb") do |file|
                    file.write(resp.body)
                end
            end
	end
	
        def extract_tar_on_windows(filename,target)
            Gem::Package::TarReader.new(Zlib::GzipReader.open(filename)).each do |entry|
                newname = File.join(target,entry.full_name.slice(entry.full_name.index('/'),entry.full_name.size))
                if(entry.directory?)
                    FileUtils.mkdir_p(newname)
                end
                if(entry.file?)
                    dir = newname.slice(0,newname.rindex('/'))
                    if(!File.directory?(dir))
                        FileUtils.mkdir_p(dir)
                    end
                    open(newname, "wb") do |file|
                        file.write(entry.read)
                    end
                end
            end
        end
	
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
                    open @url, :content_length_proc => lambda { |v| size = v } do |file| 
                        mtime = file.last_modified
                    end
                end

                if mtime && size
                    do_update = (size != cached_size || mtime > cached_mtime)
                elsif mtime
                    package.warn "%s: archive size is not available for #{@url}, relying on modification time"
                    do_update = (mtime > cached_mtime)
                elsif size
                    package.warn "%s: archive modification time is not available for #{@url}, relying on size"
                    do_update = (size != cached_size)
                else
                    package.warn "%s: neither the archive size nor its modification time available for #{@url}, will always update"
                    do_update = true
                end
            end

            if do_update
                FileUtils.mkdir_p(cachedir)
                begin
                    if(WINDOWS)
                        get_url_on_windows(@url, "#{cachefile}.partial")
                    elsif Autobuild.bsd?
                        package.run(:import, Autobuild.tool('curl'), '-Lso',"#{cachefile}.partial", @url)
                    else
                        additional_options = []
                        if timeout = self.timeout
                            additional_options << "--timeout" << timeout
                        end
                        if retries = self.retries
                            additional_options << "--tries" << retries
                        end
                        package.run(:import, Autobuild.tool('wget'), '-q', '-P', cachedir, *additional_options, @url, '-O', "#{cachefile}.partial", retry: true)
                    end
                rescue Exception
                    FileUtils.rm_f "#{cachefile}.partial"
                    raise
                end
                FileUtils.mv "#{cachefile}.partial", cachefile
            end

            @cachefile_digest = Digest::SHA1.hexdigest File.read(cachefile)

            do_update
        end

	# The source URL
        attr_reader :url
	# The local file (either a downloaded file if +url+ is not local, or +url+ itself)
	attr_reader :cachefile
        # The SHA1 digest of the current cachefile. It is updated only once the
        # cachefile has been downloaded
        #
        # @return [String] hexadecimal SHA1 digest of the file
        attr_reader :cachefile_digest
	# The unpack mode. One of Zip, Bzip, Gzip or Plain
	attr_reader :mode
	# The directory in which remote files are cached
        #
        # Defaults to ArchiveImporter.cachedir
        attr_reader :cachedir

        # Changes the cache directory for this importer
        def cachedir=(dir)
            @cachedir = dir
            relocate(@url.to_s)
        end

	# The directory contained in the tar file
        #
        # DEPRECATED use #archive_dir instead
	def tardir; @options[:tardir] end
        # The directory contained in the archive. If not set, we assume that it
        # is the same than the source dir
        def archive_dir; @options[:archive_dir] || tardir end

        # The number of time we should retry downloading if the underlying tool
        # supports it (wget does).
        #
        # It defaults to the global ArchiveImporter.retries
        attr_accessor :retries

        # The filename that should be used locally (for remote files)
        #
        # This is usually inferred by using the URL's basename, but some
        # download URLs do not allow this (for instance bitbucket tarballs)
        #
        # Change it by calling {relocate}
        #
        # @retun [String]
        attr_reader :filename

        # The timeout (in seconds) used during downloading.
        #
        # With wget, it is the timeout used for DNS resolution, connection and
        # idle time (time without receiving data)
        #
        # It defaults to the global ArchiveImporter.timeout
        attr_accessor :timeout

        # Tests whether the archive's content is stored within a subdirectory or
        # not
        #
        # If it has a subdirectory, its name is assumed to be the package's
        # basename, or the value returned by {archive_dir} if the archive_dir
        # option was given to {initialize}
        def has_subdirectory?
            !@options[:no_subdirectory]
        end

	# Creates a new importer which downloads +url+ in +cachedir+ and unpacks it. The following options
	# are allowed:
	# [:cachedir] the cache directory. Defaults to "#{Autobuild.prefix}/cache"
        # [:archive_dir] the directory contained in the archive file. If set,
        #       the importer will rename that directory to make it match
        #       Package#srcdir
        # [:no_subdirectory] the archive does not have the custom archive
        #       subdirectory.
        # [:retries] The number of retries for downloading
        # [:timeout] The timeout (in seconds) used during downloading, it defaults to 10s
        # [:filename] Rename the archive to this filename (in cache) -- will be
        #       also used to infer the mode
        # [:mode] The unpack mode: one of Zip, Bzip, Gzip or Plain, this is
        #       usually automatically inferred from the filename
        def initialize(url, options)
            sourceopts, options = Kernel.filter_options options,
                :source_id, :repository_id, :filename, :mode
            super(options)

            if !@options.has_key?(:update_cached_file)
                @options[:update_cached_file] = false
            end
            @cachedir = @options[:cachedir] || ArchiveImporter.cachedir
            @retries = @options[:retries] || ArchiveImporter.retries
            @timeout = @options[:timeout] || ArchiveImporter.timeout
            relocate(url, sourceopts)
        end

        # Changes the URL from which we should pick the archive
        def relocate(url, options = Hash.new)
            parsed_url = URI.parse(url)
            @url = parsed_url
            if !VALID_URI_SCHEMES.include?(@url.scheme)
                raise ConfigException, "invalid URL #{@url} (local files must be prefixed with file://)" 
            end
            @repository_id = options[:repository_id] || parsed_url
            @source_id = options[:source_id] || parsed_url

            @filename = options[:filename] || @filename || File.basename(url).gsub(/\?.*/, '')

            @mode = options[:mode] || ArchiveImporter.find_mode_from_filename(filename) || @mode
            if @url.scheme == 'file'
                @cachefile = @url.path
            else
                @cachefile = File.join(cachedir, filename)
            end
        end

        def update(package, options = Hash.new) # :nodoc:
            if options[:only_local]
                package.warn "%s: the archive importer does not support local updates, skipping"
                return
            end
            needs_update = update_cache(package)

            if !File.file?(checkout_digest_stamp(package))
                write_checkout_digest_stamp(package)
            end

            if needs_update || archive_changed?(package)
                checkout(package)
            end
        rescue OpenURI::HTTPError
            raise Autobuild::Exception.new(package.name, :import)
        end

        def checkout_digest_stamp(package)
            File.join(package.srcdir, "archive-autobuild-stamp")
        end

        def write_checkout_digest_stamp(package)
            File.open(checkout_digest_stamp(package), 'w') do |io|
                io.write cachefile_digest
            end
        end

        # Returns true if the archive that has been used to checkout this
        # package is different from the one we are supposed to checkout now
        def archive_changed?(package)
            checkout_digest = File.read(checkout_digest_stamp(package)).strip
            checkout_digest != cachefile_digest
        end

        def checkout(package) # :nodoc:
            update_cache(package)

            # Check whether the archive file changed, and if that is the case
            # then ask the user about deleting the folder
            if File.file?(checkout_digest_stamp(package)) && archive_changed?(package)
                if ArchiveImporter.auto_update?
                    response = 'yes'
                else
                    package.progress_done
                    package.message "The archive #{@url.to_s} is different from the one currently checked out at #{package.srcdir}", :bold
                    package.message "I will have to delete the current folder to go on with the update"
                    response = HighLine.new.ask "  Continue (yes or no) ? If no, this update will be ignored, which can lead to build problems.", String do |q|
                        q.overwrite = true
                        q.in = ['yes', 'no']
                        q.default = 'yes'
                        q.case = :downcase
                    end
                end

                if response == "no"
                    package.message "not updating #{package.srcdir}"
                    package.progress_done
                    return
                else
                    package.message "deleting #{package.srcdir} to update to new archive"
                    FileUtils.rm_rf package.srcdir
                    package.progress "checking out %s"
                end
            end

            # Un-apply any existing patch so that, when the files get
            # overwritten by the new checkout, the patch are re-applied
            patch(package, [])

            base_dir = File.dirname(package.srcdir)

            if mode == Zip
                main_dir = if @options[:no_subdirectory] then package.srcdir
                           else base_dir
                           end

                FileUtils.mkdir_p base_dir
                cmd = [ '-o', cachefile, '-d', main_dir ]
                package.run(:import, Autobuild.tool('unzip'), *cmd)
                
                archive_dir = (self.archive_dir || File.basename(package.name))
                if archive_dir != File.basename(package.srcdir)
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
				
                if(WINDOWS)
                    extract_tar_on_windows(cachefile,package.srcdir)
                else
                    package.run(:import, Autobuild.tool('tar'), *cmd)
                end
            end
            write_checkout_digest_stamp(package)

        rescue OpenURI::HTTPError
            raise Autobuild::PackageException.new(package.name, :import)
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

