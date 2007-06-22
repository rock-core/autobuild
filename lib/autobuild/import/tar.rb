require 'autobuild/importer'
require 'open-uri'

module Autobuild
    class TarImporter < Importer
	# The tarball is not compressed
        Plain = 0
	# The tarball is compressed with gzip
        Gzip  = 1
	# The tarball is compressed using bzip
        Bzip  = 2

        TAR_OPTION = {
            Plain => '',
            Gzip => 'z',
            Bzip => 'j'
        }

	# Known URI schemes for +url+
        VALID_URI_SCHEMES = [ 'file', 'http', 'https', 'ftp' ]

	# Returns the unpack mode from the file name
        def self.url_to_mode(url)
            ext = File.extname(url)
            unless ext == '.tar'
                raise "Invalid file type in #{url}" unless File.basename(url, ext) != '.tar'
            end
            mode =  case ext
                        when '.tar'; Plain
                        when '.gz';  Gzip
			when '.tgz'; Gzip
                        when '.bz2'; Bzip
                    end

            mode
        end

	# Updates the downloaded file in cache only if it is needed
        def update_cache
            do_update = true

            if File.file?(cachefile)
                cached_size = File.lstat(cachefile).size
                cached_mtime = File.lstat(cachefile).mtime

                size, mtime = nil
                open @url, :content_length_proc => lambda { |size| } do |file| 
                    mtime = file.last_modified
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
                end
            end

            if do_update
                puts "downloading #{url}"
                FileUtils.mkdir_p(cachedir)
                File.open(cachefile, 'w') do |cache|
                    open @url do |file|
                        while block = file.read(4096)
                            cache.write block
                        end
                    end
                end
                true
            end
        end

	# Sets the source URL and update +cachefile+ and +mode+ attributes accordingly.
        def url=(url)
            @url = URI.parse(url)
            raise ConfigException, "invalid URL #{@url}" unless VALID_URI_SCHEMES.include?(@url.scheme)

            @mode = TarImporter.url_to_mode(url)
            if @url.scheme == 'file'
                @cachefile = @url.path
            else
                @cachefile = File.join(cachedir, File.basename(@url.path))
            end
        end

	# The source URL
        attr_reader :url
	# The local file (either a downloaded file if +url+ is not local, or +url+ itself)
	attr_reader :cachefile
	# The unpack mode. One of Bzip, Gzip or Plain
	attr_reader :mode
	# The directory in which remote files are cached
        def cachedir; @options[:cachedir] end
	# The directory contained in the tar file
	def tardir; @options[:tardir] end

	# Creates a new importer which downloads +url+ in +cachedir+ and unpacks it. The following options
	# are allowed:
	# [:cachedir] the cache directory. Defaults to "#{Autobuild.prefix}/cache"
	# [:tardir]   the directory contained in the tar file. If set, the importer will rename that directory
	#             to make it match Package#srcdir
        def initialize(url, options)
            @options = options.dup
            @options[:cachedir] ||= "#{Autobuild.prefix}/cache"
            self.url = url
        end

        def update(package) # :nodoc:
            checkout(package) if update_cache
        rescue OpenURI::HTTPError
            raise Autobuild::Exception.new(package.name, :import)
        end

        def checkout(package) # :nodoc:
            update_cache

            base_dir = File.dirname(package.srcdir)
            FileUtils.mkdir_p base_dir
            cmd = [ 'tar', "x#{TAR_OPTION[mode]}f", cachefile, '-C', base_dir ]

            Subprocess.run(package.name, :import, *cmd)
	    if tardir
		File.mv File.join(base_dir, tardir), package.srcdir
	    end

        rescue OpenURI::HTTPError
            raise Autobuild::Exception.new(package.name, :import)
        rescue SubcommandFailed
            FileUtils.rm_f cachefile
            raise
        end
    end

    # Creates an importer which downloads a tarball from +source+ and unpacks
    # it. The allowed values in +options+ are described in TarImporter.new.
    def self.tar(source, options = {})
	TarImporter.new(source, options)
    end
end

