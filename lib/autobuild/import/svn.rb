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
            options = Kernel.validate_options options,
                :svnup => [], :svnco => [], :revision => nil

            @source = [*source].join("/")
            @program    = Autobuild.tool('svn')
            @options_up = [*options[:svnup]]
            @options_co = [*options[:svnco]]
            if rev = options[:revision]
                @options_up << "--revision" << rev
                @options_co << "--revision" << rev
            end
            super(options)
        end

        # Returns a string that identifies the remote repository uniquely
        #
        # This is meant for display purposes
        def repository_id
            @source.dup
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
                Subprocess.run(package, :import, @program, 'up', "--non-interactive", *@options_up)
            }
        end

        def checkout(package) # :nodoc:
            options = [ @program, 'co', "--non-interactive" ] + @options_co + [ @source, package.srcdir ]
            Subprocess.run(package, :import, *options)
        end
    end

    # Creates a subversion importer which import the source for the Subversion
    # URL +source+. The allowed values in +options+ are described in SVN.new.
    def self.svn(source, options = {})
        SVN.new(source, options)
    end
end

