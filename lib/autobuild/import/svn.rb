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
            svnopts, common = Kernel.filter_options options,
                :svnup => [], :svnco => [], :revision => nil,
                :repository_id => "svn:#{@source}"
            @program    = Autobuild.tool('svn')
            @options_up = [*svnopts[:svnup]]
            @options_co = [*svnopts[:svnco]]
            if rev = svnopts[:revision]
                @options_up << "--revision" << rev
                @options_co << "--revision" << rev
            end
            super(common.merge(repository_id: svnopts[:repository_id]))
        end

        private

        def update(package,only_local=false) # :nodoc:
            if only_local
                Autobuild.warn "The importer #{self.class} does not support local updates, skipping #{self}"
                return
            end
            Dir.chdir(package.importdir) do
		old_lang, ENV['LC_ALL'] = ENV['LC_ALL'], 'C'
                svninfo = []
                begin
                    Subprocess.run(package, :import, @program, 'info') do |line|
                        svninfo << line
                    end
                rescue SubcommandFailed => e
                    if svninfo.find { |l| l =~ /svn upgrade/ }
                        # Try svn upgrade and info again
                        Subprocess.run(package, :import, @program, 'upgrade')
                        svninfo.clear
                        Subprocess.run(package, :import, @program, 'info') do |line|
                            svninfo << line
                        end
                    else raise
                    end
                end
		ENV['LC_ALL'] = old_lang
		unless url = svninfo.grep(/^URL: /).first
		    if svninfo.grep(/is not a working copy/).empty?
			raise ConfigException.new(package, 'import'), "#{package.importdir} is not a Subversion working copy"
		    else
			raise ConfigException.new(package, 'import'), "Bug: cannot get SVN information for #{package.importdir}"
		    end
		end
		url.chomp =~ /URL: (.+)/
		source = $1
		if source != @source
		    raise ConfigException.new(package, 'import'), "current checkout found at #{package.importdir} is from #{source}, was expecting #{@source}"
		end
                Subprocess.run(package, :import, @program, 'up', "--non-interactive", *@options_up)
            end
        end

        def checkout(package) # :nodoc:
            options = [ @program, 'co', "--non-interactive" ] + @options_co + [ @source, package.importdir ]
            Subprocess.run(package, :import, *options)
        end
    end

    # Creates a subversion importer which import the source for the Subversion
    # URL +source+. The allowed values in +options+ are described in SVN.new.
    def self.svn(source, options = {})
        SVN.new(source, options)
    end
end

