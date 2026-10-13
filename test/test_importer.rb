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

        describe "retrying imports" do
            before do
                @importer = Importer.new(retry_count: 3)
            end

            def failure(*output)
                error = SubcommandFailed.new('test', 'git clone', '/log', 1, output)
                error.retry = true
                error
            end

            describe "#permanent_error?" do
                it "reports an error the remote will reject again as permanent" do
                    assert @importer.permanent_error?(
                        failure("fatal: could not read Username for "\
                                "'https://github.com': No such device or address")
                    )
                end

                it "reports an error that may succeed later as not permanent" do
                    refute @importer.permanent_error?(
                        failure("fatal: the remote end hung up unexpectedly")
                    )
                end

                it "treats an unrecognized error as not permanent" do
                    refute @importer.permanent_error?(failure("fatal: something new"))
                end

                it "treats an error without output as not permanent" do
                    refute @importer.permanent_error?(Class.new(RuntimeError).new)
                end
            end

            describe "#update_retry_count" do
                it "does not retry a permanent error" do
                    assert_nil @importer.update_retry_count(
                        failure("remote: HTTP Basic: Access denied."), 0
                    )
                end

                it "retries an error that may succeed later" do
                    assert_equal 1, @importer.update_retry_count(
                        failure("fatal: early EOF"), 0
                    )
                end

                it "stops once retry_count is reached" do
                    assert_nil @importer.update_retry_count(failure("fatal: early EOF"), 3)
                end

                it "does not retry an error that is not marked as retryable" do
                    error = failure("fatal: early EOF")
                    error.retry = false
                    assert_nil @importer.update_retry_count(error, 0)
                end
            end

            describe "#retry_delay" do
                it "does not wait at all by default" do
                    assert_equal 0, @importer.retry_delay(1)
                end

                it "does not wait for a negative base delay" do
                    @importer.retry_base_delay = -1
                    assert_equal 0, @importer.retry_delay(1)
                end

                it "doubles the delay with every attempt" do
                    @importer.retry_base_delay = 2
                    assert_equal 2, @importer.retry_delay(1)
                    assert_equal 4, @importer.retry_delay(2)
                    assert_equal 8, @importer.retry_delay(3)
                end

                it "caps the delay at retry_max_delay" do
                    @importer.retry_base_delay = 2
                    @importer.retry_max_delay = 5
                    assert_equal 5, @importer.retry_delay(10)
                end
            end

            describe "#error_summary" do
                it "reports the first non-empty output line" do
                    assert_equal "fatal: early EOF",
                                 @importer.error_summary(failure("", "fatal: early EOF"))
                end

                it "falls back to the error class without usable output" do
                    error = Class.new(RuntimeError).new
                    assert_equal error.class.name, @importer.error_summary(error)
                end
            end
        end
    end
end
