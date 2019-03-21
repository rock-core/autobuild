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
            hgopts, _common = Kernel.filter_options options,
                branch: 'default'
            sourceopts, common = Kernel.filter_options options,
                :repository_id, :source_id

            super(common)
            @branch = hgopts[:branch]
            relocate(repository, sourceopts)
        end

        # Changes the repository this importer is pointing to
        def relocate(repository, options = Hash.new)
            @repository = repository
            @repository_id =
                options[:repository_id] ||
                "hg:#{@repository}"
            @source_id =
                options[:source_id] ||
                "#{repository_id} branch=#{branch}"
        end

        # The remote repository URL.
        attr_accessor :repository

        # The tip this importer is tracking
        attr_accessor :branch

        # Raises ConfigException if the current directory is not a hg
        # repository
        def validate_importdir(package)
            unless File.directory?(File.join(package.importdir, '.hg'))
                raise ConfigException.new(package, 'import'),
                    "while importing #{package.name}, "\
                    "#{package.importdir} is not a hg repository"
            end
        end

        def update(package, options = Hash.new)
            if options[:only_local]
                package.warn "%s: the Mercurial importer does not support "\
                    "local updates, skipping"
                return false
            end
            validate_importdir(package)
            package.run(:import, Autobuild.tool('hg'), 'pull',
                repository, retry: true, working_directory: package.importdir)
            package.run(:import, Autobuild.tool('hg'), 'update',
                branch, working_directory: package.importdir)
            true # no easy to know if package was updated, keep previous behavior
        end

        def checkout(package, _options = Hash.new)
            base_dir = File.expand_path('..', package.importdir)
            FileUtils.mkdir_p(base_dir) unless File.directory?(base_dir)

            package.run(:import, Autobuild.tool('hg'), 'clone',
                '-u', branch, repository, package.importdir, retry: true)
        end
    end

    # Creates a hg importer which gets the source for the given repository and
    # branch URL +source+.
    #
    # @param (see Hg#initialize)
    def self.hg(repository, options = {})
        Hg.new(repository, options)
    end
end
