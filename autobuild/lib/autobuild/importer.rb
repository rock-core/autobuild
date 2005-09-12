class Importer
    def initialize(options)
        @options = options
    end

    def import(package)
        srcdir = package.srcdir
        if File.directory?(srcdir)
            if $UPDATE
                update(package)
            else
                puts "Not updating #{package.target}"
                return
            end

        elsif File.exists?(srcdir)
            raise ImportException, "#{srcdir} exists but is not a directory"
        else
            begin
                checkout(package)
                #patch(package)
            rescue ImportException => error
                FileUtils.rm_rf package.srcdir
                raise error
            end
        end
    end

    def patch(package)
        patch = $PROGRAMS['patch'] || 'patch'
        # Apply patches, if any
        @options[:patch].to_a.each do |path|
            subcommand(package.target, 'patch', patch, "<#{path}")
        end
    end
end

