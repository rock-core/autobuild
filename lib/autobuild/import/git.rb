require 'fileutils'
require 'autobuild/subcommand'
require 'autobuild/importer'

module Autobuild
    class Git < Importer
        # Creates an importer which tracks the given repository
        # and branch. +source+ is [repository, branch]
        #
        # This importer uses the 'git' tool to perform the
        # import. It defaults to 'svn' and can be configured by
        # doing 
	#   Autobuild.programs['git'] = 'my_git_tool'
        def initialize(repository, branch = nil, options = {})
            @repository = repository.to_str
            @branch     = branch || 'master'
            super(options)
        end

        attr_accessor :repository
        attr_accessor :branch

        # True if it is allowed to merge remote updates automatically. If false
        # (the default), the import will fail if the updates do not resolve as
        # a fast-forward
        def merge?; !!@merge end

        # Set the merge flag. See #merge?
        def merge=(flag); @merge = flag end

        def update(package)
            Dir.chdir(package.srcdir) do
                if !File.directory?('.git')
                    raise ConfigException, "#{package.srcdir} is not a git repository"
                end

                # Fetch and merge if the merge leads to a fast-forward
                Subprocess.run(package.name, :import, Autobuild.tool('git'), 'fetch', repository)
                if !File.readable?( File.join('.git', 'FETCH_HEAD') )
                    return
                end

                fetch_commit = File.readlines( File.join('.git', 'FETCH_HEAD') ).
                    delete_if { |l| l =~ /not-for-merge/ }
                return if fetch_commit.empty?
                fetch_commit = fetch_commit.first.split(/\s+/).first

                common_commit = `git merge-base HEAD #{fetch_commit}`.chomp
                head_commit   = `git rev-parse HEAD`.chomp

                if common_commit != fetch_commit
                    if merge? || common_commit == head_commit
                        Subprocess.run(package.name, :import, Autobuild.tool('git'), 'merge', fetch_commit)
                    else
                        raise "importing the current version would lead to a non fast-forward"
                    end
                end
            end
        end

        def checkout(package)
            base_dir = File.expand_path('..', package.srcdir)
            if !File.directory?(base_dir)
                FileUtils.mkdir_p base_dir
            end

            Subprocess.run(package.name, :import,
                Autobuild.tool('git'), 'clone', '-o', 'autobuild',
                repository, package.srcdir)

            Dir.chdir(package.srcdir) do
                Subprocess.run(package.name, :import, Autobuild.tool('git'),
                    'reset', '--hard', "autobuild/#{branch}")
            end
        end
    end

    # Creates a git importer which gets the source for the given repository and branch
    # URL +source+. The allowed values in +options+ are described in SVN.new.
    def self.git(repository, branch, options = {})
        Git.new(repository, branch, options)
    end
end

