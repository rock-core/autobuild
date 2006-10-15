require 'autobuild/subcommand'
require 'autobuild/importer'

module Autobuild
    class SVN < Importer
        def initialize(source, options = {})
            @source = [*source].join("/")
            @program    = Autobuild.tool('svn')
            @options_up = [*options[:svnup]]
            @options_co = [*options[:svnco]]
            super(options)
        end

        private

        def update(package)
            Dir.chdir(package.srcdir) {
		url = IO.popen("svn info") { |io| io.readlines }.grep(/^URL: /).first.chomp
		url =~ /URL: (.+)/
		source = $1
		if source != @source
		    raise ArgumentError, "current checkout found at #{package.srcdir} is from #{source}, was expecting #{@source}"
		end
                Subprocess.run(package.name, :import, @program, 'up', *@options_up)
            }
        end

        def checkout(package)
            options = [ @program, 'co' ] + @options_co + [ @source, package.srcdir ]
            Subprocess.run(package.name, :import, *options)
        end
    end

    def self.svn(source, options = {})
        SVN.new(source, options)
    end
end

