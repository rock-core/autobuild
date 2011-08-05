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
        def initialize(root_name, options = {})
            cvsopts, common = Kernel.filter_options options, :module => nil, :cvsup => '-dP', :cvsco => '-P'
            @root   = root_name
            @module = cvsopts[:module]
            if !@module
                raise ArgumentError, "no module given"
            end

            @program    = Autobuild.tool('cvs')
            @options_up = cvsopts[:cvsup] || '-dP'
            @options_up = Array[*@options_up]
            @options_co = cvsopts[:cvsco] || '-P'
            @options_co = Array[*@options_co]
            super(common)
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
                Subprocess.run(package, :import, @program, 'up', *@options_up)
	    end
        end

        def checkout(package) # :nodoc:
            head, tail = File.split(package.srcdir)
            cvsroot = @root
               
            FileUtils.mkdir_p(head) if !File.directory?(head)
            Dir.chdir(head) do
                options = [ @program, '-d', cvsroot, 'co', '-d', tail ] + @options_co + [ modulename ]
                Subprocess.run(package, :import, *options)
	    end
        end
    end

    # Returns the CVS importer which will get the +name+ module in repository
    # +repo+. The allowed values in +options+ are described in CVSImporter.new.    
    def self.cvs(module_name, options = {}, backward_compatibility = nil)
        if backward_compatibility
            backward_compatibility[:module] = options
            CVSImporter.new(module_name, backward_compatibility)
        else
            CVSImporter.new(module_name, options)
        end
    end
end

