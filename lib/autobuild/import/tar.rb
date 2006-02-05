require 'open-uri'

module Autobuild
    class TarImporter < Importer
        Plain = 0
        Gzip  = 1
        Bzip  = 2

        TAR_OPTION = {
            Plain => '',
            Gzip => 'z',
            Bzip => 'j'
        }

        VALID_URI_SCHEMES = [ 'file', 'http', 'ftp' ]

        def self.url_to_mode(url)
            ext = File.extname(url)
            mode =  case ext
                        when '.tar'; Plain
                        when '.gz'; Gzip
                        when '.bz2'; Bzip
                    end

            unless ext == '.tar'
                raise "Invalid file type in #{url}" unless File.basename(url, ext) != '.tar'
            end
            mode
        end

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

        def url=(url)
            @url = URI.parse(url)
            raise ConfigException, "invalid URL #{url}" unless VALID_URI_SCHEMES.include?(@url.scheme)

            @mode = TarImporter.url_to_mode(url)
            if @url.scheme == 'file'
                @cachefile = @url
            else
                @cachefile = File.join(cachedir, File.basename(@url.path))
            end
        end

        attr_reader :url, :cachefile, :mode
        def cachedir; @options[:cachedir] end

        def initialize(url, options)
            @options = options.dup
            @options[:cachedir] ||= $CACHEDIR
            self.url = url
        end

        def update(package)
            checkout if update_cache
        rescue OpenURI::HTTPError
            raise Autobuild::Exception.new(package.name, :import)
        end

        def checkout(package)
            update_cache

            base_dir = File.dirname(package.srcdir)
            FileUtils.mkdir_p base_dir
            cmd = [ 'tar', "x#{TAR_OPTION[mode]}f", cachefile, '-C', base_dir ]
            
            Subprocess.run(package.name, :import, *cmd)

        rescue OpenURI::HTTPError
            raise Autobuild::Exception.new(package.name, :import)
        rescue SubcommandFailed
            FileUtils.rm_f cachefile
            raise
        end
    end

    module Import
        def self.tar(source, package_options)
            TarImporter.new(source, package_options)
        end
    end
end

