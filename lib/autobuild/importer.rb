class Importer
    def import(package)
        srcdir = package.srcdir
        if File.directory?(srcdir)
            if $NOUPDATE
                puts "Not updating #{package.target} since noupdate is set"
                return
            end

            update(package)

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

