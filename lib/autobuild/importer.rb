class Importer
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
            rescue ImportException => error
                FileUtils.rm_rf package.srcdir
                raise error
            end
        end
    end
end

