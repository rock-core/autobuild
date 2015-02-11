require 'autobuild/test'

describe 'Autobuild environment management' do
    describe "an inherited environment variable" do
        before do
            Autobuild::ORIGINAL_ENV['AUTOBUILD_TEST'] = "val1:val0"
            Autobuild.env_inherit 'AUTOBUILD_TEST'
        end
        describe "#env_push_path" do
            it "adds the new path at the beginning of the variable, after the inherited environment" do
                Autobuild.env_push_path 'AUTOBUILD_TEST', 'newval1'
                Autobuild.env_push_path 'AUTOBUILD_TEST', 'newval0'
                assert_equal 'newval1:newval0:val1:val0',
                    ENV['AUTOBUILD_TEST']
            end
        end
    end
end
