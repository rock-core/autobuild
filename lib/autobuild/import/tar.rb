require 'open-uri'

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

            do_update = (size != cached_size || mtime > cached_mtime)
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
        @options = options
        self.url = url
    end

    def update(package)
        if update_cache
            checkout
        end
    end

    def checkout(package)
        update_cache
        cmd = [ 'tar', "x#{TAR_OPTION[mode]}f", cachefile ]
        
        Dir.chdir(File.dirname(package.srcdir)) {
            begin
                Subprocess.run(package.target, 'tar', *cmd)
            rescue SubcommandFailed => e
                raise ImportException.new(e), "failed to import #{modulename}"
            end
        }
    end
end

module Import
    def self.tar(source, package_options)
        CVSImporter.new(source, package_options)
    end
end

