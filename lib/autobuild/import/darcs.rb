require 'autobuild/config'
require 'autobuild/subcommand'
require 'autobuild/importer'

module Autobuild
    class DarcsImporter < Importer
	# Creates a new importer which gets the source from the Darcs repository
	# +source+ # The following values are allowed in +options+:
	# [:get] options to give to 'darcs get'.
	# [:pull] options to give to 'darcs pull'.
	#
	# This importer uses the 'darcs' tool to perform the import. It defaults
	# to 'darcs' and can be configured by doing 
	#   Autobuild.programs['darcs'] = 'my_darcs_tool'
        def initialize(source, options = {})
            @source   = source
            @program  = Autobuild.tool('darcs')
            super(options)
	    @pull = [*options[:pull]]
	    @get  = [*options[:get]]
        end
        
        private

        def update(package) # :nodoc:
	    if !File.directory?( File.join(package.srcdir, '_darcs') )
		raise ConfigException, "#{package.srcdir} is not a Darcs repository"
	    end

	    Subprocess.run(package, :import, @program, 
	       'pull', '--all', "--repodir=#{package.srcdir}", '--set-scripts-executable', @source, *@pull)
        end

        def checkout(package) # :nodoc:
	    basedir = File.dirname(package.srcdir)
	    unless File.directory?(basedir)
		FileUtils.mkdir_p(basedir)
	    end

	    Subprocess.run(package, :import, @program, 
	       'get', '--set-scripts-executable', @source, package.srcdir, *@get)
        end
    end

    # Returns the Darcs importer which will get the source from the Darcs repository
    # +source+. The allowed values in +options+ are described in DarcsImporter.new.
    def self.darcs(source, options = {})
        DarcsImporter.new(source, options)
    end
end

