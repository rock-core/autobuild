require 'autobuild/importer'
require 'digest/sha1'
require 'open-uri'
require 'fileutils'
require 'net/http'
require 'net/https'

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
        VALID_URI_SCHEMES = ['file', 'http', 'https', 'ftp']

        # Known URI schemes for +url+ on windows
        WINDOWS_VALID_URI_SCHEMES = ['file', 'http', 'https']

        class << self
            # The directory in which downloaded files are saved
            #
            # It defaults, if set, to the value returned by
            # {Importer.cache_dirs} and falls back #{prefix}/cache
            def cachedir
                if @cachedir then @cachedir
                elsif cache_dirs = Importer.cache_dirs('archives')
                    @cachedir = cache_dirs.first
                else
                    "#{Autobuild.prefix}/cache"
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
        def self.auto_update=(flag)
            @auto_update = flag
        end
        @auto_update = (ENV['AUTOBUILD_ARCHIVE_AUTOUPDATE'] == '1')

        attr_writer :update_cached_file
        def update_cached_file?
            @update_cached_file
        end

        def download_http(package, uri, filename, user: nil, password: nil,
                current_time: nil)
            request = Net::HTTP::Get.new(uri)
            if current_time
                request['If-Modified-Since'] = current_time.rfc2822
            end
            if user
                request.basic_auth user, password
            end

            Net::HTTP.start(
                uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|

                http.request(request) do |resp|
                    case resp
                    when Net::HTTPNotModified
                        return false
                    when Net::HTTPSuccess
                        if current_time && (last_modified = resp.header['last-modified'])
                            return false if current_time >= Time.rfc2822(last_modified)
                        end
                        if (length = resp.header['Content-Length'])
                            length = Integer(length)
                            expected_size = "/#{Autobuild.human_readable_size(length)}"
                        end

                        File.open(filename, 'wb') do |io|
                            size = 0
                            next_update = Time.now
                            resp.read_body do |chunk|
                                io.write chunk
                                size += chunk.size
                                if size != 0 && (Time.now > next_update)
                                    formatted_size = Autobuild.human_readable_size(size)
                                    package.progress "downloading %s "\
                                        "(#{formatted_size}#{expected_size})"
                                    next_update = Time.now + 1
                                end
                            end
                            formatted_size = Autobuild.human_readable_size(size)
                            package.progress "downloaded %s "\
                                "(#{formatted_size}#{expected_size})"
                        end
                    when Net::HTTPRedirection
                        if (location = resp.header['location']).start_with?('/')
                            redirect_uri = uri.dup
                            redirect_uri.path = resp.header['location']
                        else
                            redirect_uri = location
                        end

                        return download_http(package, URI(redirect_uri), filename,
                            user: user, password: password, current_time: current_time)
                    else
                        raise PackageException.new(package, 'import'),
                            "failed download of #{package.name} from #{uri}: #{resp.class}"
                    end
                end
            end
            true
        end

        def extract_tar_gz(io, target)
            Gem::Package::TarReader.new(io).each do |entry|
                newname = File.join(
                    target,
                    entry.full_name.slice(entry.full_name.index('/'), entry.full_name.size))
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

        def update_needed?(package)
            return true  unless File.file?(cachefile)
            return false unless update_cached_file?

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
                return size != cached_size || mtime > cached_mtime
            elsif mtime
                package.warn "%s: archive size is not available for #{@url}, relying on modification time"
                return mtime > cached_mtime
            elsif size
                package.warn "%s: archive modification time is not available for #{@url}, relying on size"
                return size != cached_size
            else
                package.warn "%s: neither the archive size nor its modification time available for #{@url}, will always update"
                return true
            end
        end

        def download_from_url(package)
            FileUtils.mkdir_p(cachedir)
            begin
                if %w[http https].include?(@url.scheme)
                    if File.file?(cachefile)
                        return false unless update_cached_file?
                        cached_mtime = File.lstat(cachefile).mtime
                    end
                    updated = download_http(package, @url, "#{cachefile}.partial",
                        user: @user, password: @password,
                        current_time: cached_mtime)
                    return false unless updated
                elsif Autobuild.bsd?
                    return false unless update_needed?(package)
                    package.run(:import, Autobuild.tool('curl'),
                                '-Lso',"#{cachefile}.partial", @url)
                else
                    return false unless update_needed?(package)
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
            true
        end

        # Updates the downloaded file in cache only if it is needed
        #
        # @return [Boolean] true if a new file was downloaded, false otherwise
        def update_cache(package)
            updated = download_from_url(package)
            @cachefile_digest = Digest::SHA1.hexdigest File.read(cachefile)
            updated
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
        def initialize(url, options = Hash.new)
            sourceopts, options = Kernel.filter_options options,
                :source_id, :repository_id, :filename, :mode, :update_cached_file,
                :user, :password
            super(options)

            @filename = nil
            @update_cached_file = false
            @cachedir = @options[:cachedir] || ArchiveImporter.cachedir
            @retries  = @options[:retries] || ArchiveImporter.retries
            @timeout  = @options[:timeout] || ArchiveImporter.timeout
            relocate(url, sourceopts)
        end

        # Changes the URL from which we should pick the archive
        def relocate(url, options = Hash.new)
            parsed_url = URI.parse(url).normalize
            @url = parsed_url
            if !VALID_URI_SCHEMES.include?(@url.scheme)
                raise ConfigException, "invalid URL #{@url} (local files "\
                    "must be prefixed with file://)"
            elsif Autobuild.windows?
                unless WINDOWS_VALID_URI_SCHEMES.include?(@url.scheme)
                    raise ConfigException, "downloading from a #{@url.scheme} URL "\
                        "is not supported on windows"
                end
            end

            @repository_id = options[:repository_id] || parsed_url.to_s
            @source_id     = options[:source_id] || parsed_url.to_s

            @filename = options[:filename] || @filename || File.basename(url).gsub(/\?.*/, '')
            @update_cached_file = options[:update_cached_file]

            @mode = options[:mode] || ArchiveImporter.find_mode_from_filename(filename) || @mode
            if Autobuild.windows? && (mode != Gzip)
                raise ConfigException, "only gzipped tar archives are supported on Windows"
            end
            @user = options[:user]
            @password = options[:password]
            if @user && !%w[http https].include?(@url.scheme)
                raise ConfigException, "authentication is only supported for http and https URIs"
            end

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
                checkout(package, allow_interactive: options[:allow_interactive])
                true
            end
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

        def checkout(package, options = Hash.new) # :nodoc:
            options = Kernel.validate_options options,
                allow_interactive: true

            update_cache(package)

            # Check whether the archive file changed, and if that is the case
            # then ask the user about deleting the folder
            if File.file?(checkout_digest_stamp(package)) && archive_changed?(package)
                if ArchiveImporter.auto_update?
                    response = 'yes'
                elsif options[:allow_interactive]
                    package.progress_done
                    package.message "The archive #{@url.to_s} is different from the one currently checked out at #{package.srcdir}", :bold
                    package.message "I will have to delete the current folder to go on with the update"
                    response = TTY::Prompt.new.ask "  Continue (yes or no) ? If no, this update will be ignored, which can lead to build problems.", convert: :bool
                else
                    raise Autobuild::InteractionRequired, "importing #{package.name} would have required user interaction and allow_interactive is false"
                end

                if !response
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

                if Autobuild.windows?
                    io = if mode == Plain
                        File.open(cachefile, 'r')
                    else
                        Zlib::GzipReader.open(cachefile)
                    end
                    extract_tar_gz(io, package.srcdir)
                else
                    package.run(:import, Autobuild.tool('tar'), *cmd)
                end
            end
            write_checkout_digest_stamp(package)

        rescue SubcommandFailed
            if cachefile != url.path
                FileUtils.rm_f cachefile
            end
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
