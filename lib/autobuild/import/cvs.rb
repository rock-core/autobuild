require 'autobuild/config'
require 'autobuild/subcommand'
require 'autobuild/importer'

module Autobuild
    class CVSImporter < Importer
        def initialize(root, name, options = {})
            @root = root
            @module = name

            @program    = Autobuild.tool('cvs')
            @options_up = options[:cvsup] || '-dP'
            @options_up = Array[*@options_up]
            @options_co = options[:cvsco] || '-P'
            @options_co = Array[*@options_co]
            super(options)
        end
        
        def modulename
            @module
        end

        private

        def update(package)
            Dir.chdir(package.srcdir) do
		if !File.exists?("#{package.srcdir}/CVS/Root")
		    raise ConfigException, "#{package.srcdir} does not look like a CVS checkout"
		end

		root = File.open("#{package.srcdir}/CVS/Root") { |io| io.read }.chomp
		mod  = File.open("#{package.srcdir}/CVS/Repository") { |io| io.read }.chomp

		if root != @root || mod != @module
		    raise ConfigException, "checkout in #{package.srcdir} is from #{root}:#{mod}, was expecting #{@root}:#{@module}"
		end
                Subprocess.run(package.name, :import, @program, 'up', *@options_up)
	    end
        end

        def checkout(package)
            head, tail = File.split(package.srcdir)
            cvsroot = @root
               
            FileUtils.mkdir_p(head) if !File.directory?(head)
            Dir.chdir(head) {
                options = [ @program, '-d', cvsroot, 'co', '-d', tail ] + @options_co + [ modulename ]
                Subprocess.run(package.name, :import, *options)
            }
        end
    end

    def self.cvs(repo, name, package_options = {})
        CVSImporter.new(repo, name, package_options)
    end
end

