require 'autobuild/test'

describe 'Autobuild environment management' do
    after do
        Autobuild.env_reset 'AUTOBUILD_TEST'
        Autobuild.env_inherit 'AUTOBUILD_TEST', false
    end

    describe "an inherited environment variable" do
        before do
            Autobuild::ORIGINAL_ENV['AUTOBUILD_TEST'] = "val1:val0"
            Autobuild.env_inherit 'AUTOBUILD_TEST'
        end
        describe "#env_push_path" do
            it "does not re-read the inherited environment" do
            end
            it "adds the new path at the beginning of the variable, before the inherited environment" do
                Autobuild.env_push_path 'AUTOBUILD_TEST', 'newval1'
                Autobuild.env_push_path 'AUTOBUILD_TEST', 'newval0'
                assert_equal 'newval1:newval0:val1:val0',
                    ENV['AUTOBUILD_TEST']
            end
        end
        describe "#env_add_path" do
            it "does not re-read the inherited environment" do
                Autobuild::ORIGINAL_ENV['AUTOBUILD_TEST'] = 'val2:val3'
                Autobuild.env_add_path 'AUTOBUILD_TEST', 'newval'
                assert_equal 'newval:val1:val0',
                    ENV['AUTOBUILD_TEST']
            end
            it "adds the new path at the end of the variable, before the inherited environment" do
                Autobuild.env_add_path 'AUTOBUILD_TEST', 'newval0'
                Autobuild.env_add_path 'AUTOBUILD_TEST', 'newval1'
                assert_equal 'newval1:newval0:val1:val0',
                    ENV['AUTOBUILD_TEST']
            end
        end
        describe "#env_set" do
            it "does not reinitialize the inherited environment" do
                Autobuild::ORIGINAL_ENV['AUTOBUILD_TEST'] = 'val2:val3'
                Autobuild.env_set 'AUTOBUILD_TEST', 'newval'
                assert_equal 'newval:val1:val0', ENV['AUTOBUILD_TEST']
            end
            it "resets the current value to the expected one" do
                Autobuild.env_set 'AUTOBUILD_TEST', 'newval0', 'newval1'
                assert_equal 'newval0:newval1:val1:val0', ENV['AUTOBUILD_TEST']
                Autobuild.env_set 'AUTOBUILD_TEST', 'newval2', 'newval3'
                assert_equal 'newval2:newval3:val1:val0', ENV['AUTOBUILD_TEST']
            end
        end
        describe "#env_clear" do
            it "completely unsets the variable" do
                Autobuild.env_clear 'AUTOBUILD_TEST'
                assert !ENV.include?('AUTOBUILD_TEST')
            end
        end
    end

    describe "a not-inherited environment variable" do
        before do
            Autobuild::ORIGINAL_ENV['AUTOBUILD_TEST'] = "val1:val0"
            Autobuild.env_reset 'AUTOBUILD_TEST'
        end

        describe "#env_push_path" do
            it "adds the new path at the beginning of the variable" do
                Autobuild.env_push_path 'AUTOBUILD_TEST', 'newval1'
                Autobuild.env_push_path 'AUTOBUILD_TEST', 'newval0'
                assert_equal 'newval1:newval0',
                    ENV['AUTOBUILD_TEST']
            end
        end
        describe "#env_add_path" do
            it "adds the new path at the end of the variable" do
                Autobuild.env_add_path 'AUTOBUILD_TEST', 'newval0'
                Autobuild.env_add_path 'AUTOBUILD_TEST', 'newval1'
                assert_equal 'newval1:newval0',
                    ENV['AUTOBUILD_TEST']
            end
        end
        describe "#env_clear" do
            it "completely unsets the variable" do
                Autobuild.env_clear 'AUTOBUILD_TEST'
                assert !ENV.include?('AUTOBUILD_TEST')
            end
        end
    end
end
