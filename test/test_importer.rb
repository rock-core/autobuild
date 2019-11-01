require 'autobuild/test'

module Autobuild
    describe Importer do
        describe ".cache_dirs" do
            before do
                relevant = ENV.keys.grep(/^AUTOBUILD_\w+_CACHE_DIR$/)
                relevant.each { |k| ENV.delete(k) }
                ENV.delete 'AUTOBUILD_CACHE_DIR'
                Importer.unset_cache_dirs
            end
            after do
                ENV.delete 'AUTOBUILD_TEST_CACHE_DIR'
                ENV.delete 'AUTOBUILD_CACHE_DIR'
                Importer.unset_cache_dirs
            end

            describe "there is no cache set" do
                it "returns nil" do
                    assert_nil Importer.cache_dirs('test')
                end
            end
            describe "there are only specific cache dirs set" do
                before do
                    ENV['AUTOBUILD_TEST_CACHE_DIR'] = '/specific_env'
                end
                it "returns nil for a different importer" do
                    assert_nil Importer.cache_dirs('bla')
                end
                it "returns the directory for the specific importer" do
                    assert_equal ['/specific_env'], Importer.cache_dirs('test')
                end
                it "uses the explicitely set path if set" do
                    ENV.delete 'AUTOBUILD_TEST_CACHE_DIR'
                    Importer.set_cache_dirs('test', '/test')
                    assert_equal ['/test'], Importer.cache_dirs('test')
                end
                it "uses the explicitely set path over the environment if set" do
                    Importer.set_cache_dirs('test', '/test')
                    assert_equal ['/test'], Importer.cache_dirs('test')
                end
            end
            describe "the cache is not set explicitely" do
                before do
                    ENV['AUTOBUILD_TEST_CACHE_DIR'] = '/specific_env'
                    ENV['AUTOBUILD_CACHE_DIR'] = '/global_env'
                end
                it "defaults to the specific environment if known" do
                    assert_equal ['/specific_env'], Importer.cache_dirs('test')
                end
                it "falls back to the global environment otherwise" do
                    assert_equal ['/global_env/bla'], Importer.cache_dirs('bla')
                end
            end

            describe "the cache is set explicitely" do
                before do
                    Importer.set_cache_dirs 'test', '/specific'
                    Importer.default_cache_dirs = '/global'
                    ENV['AUTOBUILD_TEST_CACHE_DIR'] = '/specific_env'
                    ENV['AUTOBUILD_CACHE_DIR'] = '/global_env'
                end
                it 'normalizes default_cache_dirs to an array' do
                    assert_equal ['/global'], Importer.default_cache_dirs
                end
                it 'defaults to the specific value if known' do
                    assert_equal ['/specific'], Importer.cache_dirs('test')
                end
                it 'falls back to the global value otherwise' do
                    assert_equal ['/global/bla'], Importer.cache_dirs('bla')
                end
            end
        end
    end
end
