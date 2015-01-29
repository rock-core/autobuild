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

require 'autobuild'
require 'tmpdir'
require 'erb'
require 'fileutils'
## Uncomment this to enable flexmock
require 'flexmock/test_unit'
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
        if defined? FlexMock
            include FlexMock::ArgumentTypes
            include FlexMock::MockContainer
        end

        def setup
            @tempdir = File.join(Dir.tmpdir, "/autobuild-test-#{Process.uid}")
            FileUtils.mkdir_p(@tempdir, :mode => 0700)
            Autobuild.logdir = "#{tempdir}/log"
            FileUtils.mkdir_p Autobuild.logdir
            Autobuild.silent = true
            # Setup code for all the tests
        end

        def teardown
            Autobuild.silent = false
            if defined? FlexMock
                flexmock_teardown
            end
            super

            Autobuild::Package.clear

            if @tempdir
                FileUtils.rm_rf @tempdir
            end
        end

        def data_dir
            File.join(File.dirname(__FILE__), '..', '..', 'test', 'data')
        end

        attr_reader :tempdir

        def build_config(bind, template)
            eval "basedir = '#{self.tempdir}'", bind
            ryml = File.open(File.join(data_dir, "#{template}.ryml")) { |f| f.readlines }.join('')
            result = ERB.new(ryml).result(bind)

            yml = File.join(tempdir, "#{template}.yml")
            File.open(yml, 'w+') { |f| f.write(result) }
            
            return yml
        end

        def untar(file)
            file = File.expand_path(file, data_dir)
            dir = self.tempdir
            Dir.chdir(dir) do 
                system("tar xf #{file}")
            end

            dir
        end
    end
end

class Minitest::Test
    include Autobuild::SelfTest
end

