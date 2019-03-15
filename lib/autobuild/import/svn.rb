require 'autobuild/subcommand'
require 'autobuild/importer'
require 'rexml/document'

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
        def initialize(svnroot, options = {})
            svnroot = [*svnroot].join("/")
            svnopts, common = Kernel.filter_options options,
                :svnup => [], :svnco => [], :revision => nil,
                :repository_id => "svn:#{svnroot}"
            common[:repository_id] = svnopts.delete(:repository_id)
            relocate(svnroot, svnopts)
            super(common.merge(repository_id: svnopts[:repository_id]))
        end

        # @deprecated use {svnroot} instead
        #
        # @return [String]
        def source; svnroot end

        # Returns the SVN root
        #
        # @return [String]
        attr_reader :svnroot

        # Alias for {#svnroot}
        #
        # For consistency with the other importers
        def repository
            svnroot
        end

        attr_reader :revision

        def relocate(root, options = Hash.new)
            @svnroot = [*root].join("/")
            @options_up = [*options[:svnup]]
            @options_co = [*options[:svnco]]
            @revision = options[:revision]
            if revision
                @options_co << '--revision' << revision
                # We do not add it to @options_up as the behaviour depends on
                # the parameters given to {update} and to the state of the
                # working copy
            end
        end

        # Returns the SVN revision of the package
        #
        # @param [Package] package
        # @return [Integer]
        # @raises ConfigException if 'svn info' did not return a Revision field
        # @raises (see svn_info)
        def svn_revision(package)
            svninfo = svn_info(package)
            revision = svninfo.grep(/^Revision: /).first
            if !revision
                raise ConfigException.new(package, 'import'), "cannot get SVN information for #{package.importdir}"
            end
            revision =~ /Revision: (\d+)/
            Integer($1)
        end

        # fingerprint method returns an unique hash to identify this package,
        # for SVN the revision and URL will be used
        # @param [Package] package
        # @return [String]
        # @raises (see svn_info)
        def fingerprint(package)
            Digest::SHA1.hexdigest(svn_info(package).grep(/^(URL|Revision):/).sort.join("\n"))
        end

        # Returns the URL of the remote SVN repository
        #
        # @param [Package] package
        # @return [String]
        # @raises ConfigException if 'svn info' did not return a URL field
        # @raises (see svn_info)
        def svn_url(package)
            svninfo = svn_info(package)
            url = svninfo.grep(/^URL: /).first
            if !url
                raise ConfigException.new(package, 'import'), "cannot get SVN information for #{package.importdir}"
            end
            url.chomp =~ /URL: (.+)/
            $1
        end

        # Returns true if the SVN working copy at package.importdir has local
        # modifications
        #
        # @param [Package] package the package we want to test against
        # @param [Boolean] with_untracked_files if true, the presence of files
        #   neither ignored nor under version control will count has local
        #   modification.
        # @return [Boolean]
        def has_local_modifications?(package, with_untracked_files = false)
            status = run_svn(package, 'status', '--xml')

            not_modified = %w{external ignored none normal}
            if !with_untracked_files
                not_modified << "unversioned"
            end

            REXML::Document.new(status.join("")).
                elements.enum_for(:each, '//wc-status').
                any? do |status_item|
                    !not_modified.include?(status_item.attributes['item'].to_s)
                end
        end

        # Returns status information for package
        #
        # Given that subversion is not a distributed VCS, the only status
        # returned are either {Status::UP_TO_DATE} or {Status::SIMPLE_UPDATE}.
        # Moreover, if the status is local-only,
        # {Package::Status#remote_commits} will not be filled (querying the log
        # requires accessing the SVN server)
        #
        # @return [Package::Status]
        def status(package, only_local = false)
            status = Status.new
            status.uncommitted_code = has_local_modifications?(package)
            if only_local
                status.status = Status::UP_TO_DATE
            else
                log = run_svn(package, 'log', '-r', 'BASE:HEAD', '--xml', '.')
                log = REXML::Document.new(log.join("\n"))
                missing_revisions = log.elements.enum_for(:each, 'log/logentry').map do |l|
                    rev = l.attributes['revision']
                    date = l.elements['date'].first.to_s
                    author = l.elements['author'].first.to_s
                    msg = l.elements['msg'].first.to_s.split("\n").first
                    "#{rev} #{DateTime.parse(date)} #{author} #{msg}"
                end
                status.remote_commits = missing_revisions[1..-1]
                status.status =
                    if missing_revisions.empty?
                        Status::UP_TO_DATE
                    else
                        Status::SIMPLE_UPDATE
                    end
            end
            status
        end

        # Helper method to run a SVN command on a package's working copy
        def run_svn(package, *args, &block)
            options = Hash.new
            if args.last.kind_of?(Hash)
                options = args.pop
            end
            options, other_options = Kernel.filter_options options,
                working_directory: package.importdir, retry: true
            options = options.merge(other_options)
            package.run(:import, Autobuild.tool(:svn), *args, options, &block)
        end

        def validate_importdir(package)
            # This upgrades the local SVN filesystem if needed and checks that
            # it actually is a SVN repository in the first place
            svn_info(package)
        end

        # Returns the result of the 'svn info' command
        #
        # It automatically runs svn upgrade if needed
        #
        # @param [Package] package
        # @return [Array<String>] the lines returned by svn info, with the
        #   trailing newline removed
        # @raises [SubcommandFailed] if svn info failed
        # @raises [ConfigException] if the working copy is not a subversion
        #   working copy
        def svn_info(package)
            old_lang, ENV['LC_ALL'] = ENV['LC_ALL'], 'C'
            begin
                svninfo = run_svn(package, 'info')
            rescue SubcommandFailed => e
                if e.output.find { |l| l =~ /svn upgrade/ }
                    # Try svn upgrade and info again
                    run_svn(package, 'upgrade', retry: false)
                    svninfo = run_svn(package, 'info')
                else raise
                end
            end

            if !svninfo.grep(/is not a working copy/).empty?
                raise ConfigException.new(package, 'import'),
                    "#{package.importdir} does not appear to be a Subversion working copy"
            end
            svninfo
        ensure
            ENV['LC_ALL'] = old_lang
        end

        def update(package, options = Hash.new) # :nodoc:
            if options[:only_local]
                package.warn "%s: the svn importer does not support local updates, skipping"
                return false
            end

            url = svn_url(package)
            if url != svnroot
                raise ConfigException.new(package, 'import'), "current checkout found at #{package.importdir} is from #{url}, was expecting #{svnroot}"
            end

            options_up = @options_up.dup
            if revision
                if options[:reset] || svn_revision(package) < revision
                    options_up << '--revision' << revision
                elsif revision
                    # Don't update if the current revision is greater-or-equal
                    # than the target revision
                    return false
                end
            end

            run_svn(package, 'up', "--non-interactive", *options_up)
            true
        end

        def checkout(package, options = Hash.new) # :nodoc:
            run_svn(package, 'co', "--non-interactive", *@options_co, svnroot, package.importdir,
                    working_directory: nil)
        end
    end

    # Creates a subversion importer which import the source for the Subversion
    # URL +source+. The allowed values in +options+ are described in SVN.new.
    def self.svn(source, options = {})
        SVN.new(source, options)
    end
end

