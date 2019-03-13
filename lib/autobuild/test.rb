# simplecov must be loaded FIRST. Only the files required after it gets loaded
# will be profiled !!!
if ENV['TEST_ENABLE_COVERAGE'] == '1'
    begin
        require 'simplecov'
        SimpleCov.start
    rescue LoadError
        require 'autobuild'
        Autobuild.warn "coverage is disabled because the 'simplecov' gem cannot be loaded"
    rescue Exception => e
        require 'autobuild'
        Autobuild.warn "coverage is disabled: #{e.message}"
    end
end

require 'minitest/autorun'
require 'autobuild'
require 'tmpdir'
require 'erb'
require 'fileutils'
require 'flexmock/minitest'
require 'minitest/spec'

if ENV['TEST_ENABLE_PRY'] != '0'
    begin
        require 'pry'
    rescue Exception
        Autobuild.warn "debugging is disabled because the 'pry' gem cannot be loaded"
    end
end

module Autobuild
    # This module is the common setup for all tests
    #
    # It should be included in the toplevel describe blocks
    #
    # @example
    #   require 'autobuild/test'
    #   describe Autobuild do
    #   end
    #
    module SelfTest
        def setup
            @temp_dirs = Array.new

            @tempdir = make_tmpdir
            FileUtils.mkdir_p(@tempdir, mode: 0o700)
            Autobuild.logdir = "#{tempdir}/log"
            FileUtils.mkdir_p Autobuild.logdir
            Autobuild.silent = true
            # Setup code for all the tests
        end

        def teardown
            Autobuild.silent = false
            super

            Autobuild::Package.clear
            Rake::Task.clear

            @temp_dirs.each do |dir|
                FileUtils.rm_rf dir
            end
        end

        def make_tmpdir
            @temp_dirs << (dir = Dir.mktmpdir)
            dir
        end

        def data_dir
            File.join(File.dirname(__FILE__), '..', '..', 'test', 'data')
        end

        attr_reader :tempdir

        def build_config(bind, template)
            bind.local_variable_set(:basedir, tempdir.to_s)
            ryml = File.open(File.join(data_dir, "#{template}.ryml"), &:readlines).join('')
            result = ERB.new(ryml).result(bind)

            yml = File.join(tempdir, "#{template}.yml")
            File.open(yml, 'w+') { |f| f.write(result) }

            yml
        end

        def untar(file)
            file = File.expand_path(file, data_dir)
            dir = tempdir
            Dir.chdir(dir) do
                system("tar xf #{file}")
            end

            dir
        end

        def prepare_and_build_package(package)
            package.prepare
            Rake::Task["#{package.name}-build"].invoke
        end
    end
end

Minitest::Test.include Autobuild::SelfTest
