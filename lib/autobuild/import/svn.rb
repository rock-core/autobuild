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

        def run_svn(package, *args, &block)
            options = Hash.new
            if args.last.kind_of?(Hash)
                options = args.pop
            end
            options, other_options = Kernel.filter_options options,
                working_directory: package.importdir
            options = options.merge(other_options)
            package.run(:import, Autobuild.tool(:svn), *args, options, &block)
        end

        def svn_info(package)
            old_lang, ENV['LC_ALL'] = ENV['LC_ALL'], 'C'
            svninfo = []
            begin
                run_svn package, 'info' do |line|
                    svninfo << line
                end
            rescue SubcommandFailed
                if svninfo.find { |l| l =~ /svn upgrade/ }
                    # Try svn upgrade and info again
                    run_svn package, 'upgrade'
                    svninfo.clear
                    run_svn package, 'info' do |line|
                        svninfo << line
                    end
                else raise
                end
            end
        ensure
            ENV['LC_ALL'] = old_lang
        end

        def svn_url(package)
            svninfo = svn_info(package)
            url = svninfo.grep(/^URL: /).first
            if !url
                if !svninfo.grep(/is not a working copy/).empty?
                    raise ConfigException.new(package, 'import'), "#{package.importdir} does not appear to be a Subversion working copy"
                else
                    raise ConfigException.new(package, 'import'), "cannot get SVN information for #{package.importdir}"
                end
            end
            url.chomp =~ /URL: (.+)/
            $1
        end

        def update(package,only_local=false) # :nodoc:
            if only_local
                package.warn "%s: the svn importer does not support local updates, skipping"
                return
            end

            url = svn_url(package)
            if url != @source
                raise ConfigException.new(package, 'import'), "current checkout found at #{package.importdir} is from #{url}, was expecting #{@source}"
            end
            run_svn(package, 'up', "--non-interactive", *@options_up)
        end

        def checkout(package) # :nodoc:
            run_svn(package, 'co', "--non-interactive", *@options_co, @source, package.importdir, working_copy: nil)
        end
    end

    # Creates a subversion importer which import the source for the Subversion
    # URL +source+. The allowed values in +options+ are described in SVN.new.
    def self.svn(source, options = {})
        SVN.new(source, options)
    end
end

