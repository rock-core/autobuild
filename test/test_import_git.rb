require 'minitest/spec'
require 'minitest/autorun'
require 'autobuild'

describe Autobuild::Git do
    describe "version_compare" do
        it "should return -1 if the actual version is greater" do
            assert_equal(-1, Autobuild::Git.compare_versions([2, 1, 0], [2, 0, 1]))
        end
        it "should return 0 if the versions are equal" do
            assert_equal(0, Autobuild::Git.compare_versions([2, 1, 0], [2, 1, 0]))
        end
        it "should return 1 if the required version is greater" do
            assert_equal(1, Autobuild::Git.compare_versions([2, 0, 1], [2, 1, 0]))
            assert_equal(1, Autobuild::Git.compare_versions([1, 9, 1], [2, 1, 0]))
        end
        it "should fill missing version parts with zeros" do
            assert_equal(-1, Autobuild::Git.compare_versions([2, 1], [2, 0, 1]))
            assert_equal(-1, Autobuild::Git.compare_versions([2, 1, 0], [2, 0]))
            assert_equal(0, Autobuild::Git.compare_versions([2, 1], [2, 1, 0]))
            assert_equal(0, Autobuild::Git.compare_versions([2, 1, 0], [2, 1]))
            assert_equal(1, Autobuild::Git.compare_versions([2, 1], [2, 1, 1]))
            assert_equal(1, Autobuild::Git.compare_versions([2, 1, 1], [2, 2]))
        end
    end
    describe "at_least_version" do
        Autobuild::Git.stub :version, [1,9,1] do
            it "should be true if required version is smaller" do
                assert_equal( true, Autobuild::Git.at_least_version( 1,8,1 ) ) 
            end
            it "should be false if required version is greater" do
                assert_equal( false, Autobuild::Git.at_least_version( 2,0,1 ) )
            end
        end
    end
end
