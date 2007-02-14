require 'autobuild/subcommand'
require 'autobuild/importer'

module Autobuild
    class SVN < Importer
	# Creates an importer which gets the source for the Subversion URL +source+.
	# The following options are allowed:
	# [:svnup] options to give to 'svn up'
	# [:svnco] options to give to 'svn co'
	#
	# This importer uses the 'svn' tool to perform the import. It defaults
	# to 'svn' and can be configured by doing 
	#   Autobuild.programs['svn'] = 'my_svn_tool'
        def initialize(source, options = {})
            @source = [*source].join("/")
            @program    = Autobuild.tool('svn')
            @options_up = [*options[:svnup]]
            @options_co = [*options[:svnco]]
            super(options)
        end

        private

        def update(package) # :nodoc:
            Dir.chdir(package.srcdir) {
		old_lang, ENV['LC_ALL'] = ENV['LC_ALL'], 'C'
		svninfo = IO.popen("svn info") { |io| io.readlines }
		ENV['LC_ALL'] = old_lang
		unless url = svninfo.grep(/^URL: /).first
		    if svninfo.grep(/is not a working copy/).empty?
			raise ConfigException, "#{package.srcdir} is not a Subversion working copy"
		    else
			raise ConfigException, "Bug: cannot get SVN information for #{package.srcdir}"
		    end
		end
		url.chomp =~ /URL: (.+)/
		source = $1
		if source != @source
		    raise ConfigException, "current checkout found at #{package.srcdir} is from #{source}, was expecting #{@source}"
		end
                Subprocess.run(package.name, :import, @program, 'up', *@options_up)
            }
        end

        def checkout(package) # :nodoc:
            options = [ @program, 'co' ] + @options_co + [ @source, package.srcdir ]
            Subprocess.run(package.name, :import, *options)
        end
    end

    # Creates a subversion importer which import the source for the Subversion
    # URL +source+. The allowed values in +options+ are described in SVN.new.
    def self.svn(source, options = {})
        SVN.new(source, options)
    end
end

