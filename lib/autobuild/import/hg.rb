require 'fileutils'
require 'autobuild/subcommand'
require 'autobuild/importer'
require 'utilrb/kernel/options'

module Autobuild
    class Hg < Importer
        # Creates an importer which tracks the given repository
        # and (optionally) a branch.
        #
        # This importer uses the 'hg' tool to perform the
        # import. It defaults to 'hg' and can be configured by
        # doing 
	#   Autobuild.programs['hg'] = 'my_git_tool'
        #
        # @param [String] repository the repository URL
        # @option options [String] :branch (default) the branch to track
        def initialize(repository, options = {})
            @repository = repository.to_str

            hgopts, common = Kernel.filter_options options, :branch => 'default'
            @branch = hgopts[:branch]
            super(common)
        end

        # Returns a string that identifies the remote repository uniquely
        #
        # This is meant for display purposes
        def repository_id
            "hg:#{repository}"
        end

        # The remote repository URL.
        attr_accessor :repository

        # The tip this importer is tracking
        attr_accessor :branch

        # Raises ConfigException if the current directory is not a hg
        # repository
        def validate_importdir(package)
            if !File.directory?(File.join(package.importdir, '.hg'))
                raise ConfigException.new(package, 'import'), "while importing #{package.name}, #{package.importdir} is not a hg repository"
            end
        end

        def update(package)
            validate_importdir(package)
            Dir.chdir(package.importdir) do
                Subprocess.run(package, :import, Autobuild.tool('hg'), 'pull', repository)
                Subprocess.run(package, :import, Autobuild.tool('hg'), 'update', branch)
            end
        end

        def checkout(package)
            base_dir = File.expand_path('..', package.importdir)
            if !File.directory?(base_dir)
                FileUtils.mkdir_p base_dir
            end

            Subprocess.run(package, :import,
                Autobuild.tool('hg'), 'clone', '-u', branch, repository, package.importdir)
        end

        # Changes the repository this importer is pointing to
        def relocate(repository)
            @repository = repository
        end
    end

    # Creates a hg importer which gets the source for the given repository and branch
    # URL +source+.
    #
    # @param (see Hg#initialize)
    def self.hg(repository, options = {})
        Hg.new(repository, options)
    end
end

