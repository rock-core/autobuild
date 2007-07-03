require 'autobuild/config'
require 'autobuild/subcommand'
require 'autobuild/importer'

module Autobuild
    class CVSImporter < Importer
	# Creates a new importer which gets the module +name+ from the
	# repository in +root+. The following values are allowed in +options+:
	# [:cvsup] options to give to 'cvs up'. Default: -dP.
	# [:cvsco] options to give to 'cvs co'. Default: -P.
	#
	# This importer uses the 'cvs' tool to perform the import. It defaults
	# to 'cvs' and can be configured by doing 
	#   Autobuild.programs['cvs'] = 'my_cvs_tool'
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

	# Array of options to give to 'cvs checkout'
	attr_reader :options_co
	# Array of options to give to 'cvs update'
	attr_reader :options_up
        
	# Returns the module to get
        def modulename; @module end

        private

        def update(package) # :nodoc:
            Dir.chdir(package.srcdir) do
		if !File.exists?("#{package.srcdir}/CVS/Root")
		    raise ConfigException, "#{package.srcdir} is not a CVS working copy"
		end

		root = File.open("#{package.srcdir}/CVS/Root") { |io| io.read }.chomp
		mod  = File.open("#{package.srcdir}/CVS/Repository") { |io| io.read }.chomp

		# Remove any :ext: in front of the root
		root = root.gsub /^:ext:/, ''
		expected_root = @root.gsub /^:ext:/, ''
		# Remove the optional ':' between the host and the path
		root = root.gsub /:/, ''
		expected_root = expected_root.gsub /:/, ''

		if root != expected_root || mod != @module
		    raise ConfigException, "checkout in #{package.srcdir} is from #{root}:#{mod}, was expecting #{expected_root}:#{@module}"
		end
                Subprocess.run(package.name, :import, @program, 'up', *@options_up)
	    end
        end

        def checkout(package) # :nodoc:
            head, tail = File.split(package.srcdir)
            cvsroot = @root
               
            FileUtils.mkdir_p(head) if !File.directory?(head)
            Dir.chdir(head) {
                options = [ @program, '-d', cvsroot, 'co', '-d', tail ] + @options_co + [ modulename ]
                Subprocess.run(package.name, :import, *options)
            }
        end
    end

    # Returns the CVS importer which will get the +name+ module in repository
    # +repo+. The allowed values in +options+ are described in CVSImporter.new.    
    def self.cvs(repo, name, options = {})
        CVSImporter.new(repo, name, options)
    end
end

