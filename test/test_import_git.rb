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
end
