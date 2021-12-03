# frozen_string_literal: true

require 'autobuild/test'

module Autobuild
    describe Python do
        attr_reader :root_dir, :package, :prefix

        before do
            @root_dir = make_tmpdir
            @package = Autobuild.python :package
            @prefix = File.join(root_dir, "python-prefix")

            package.prefix = @prefix
        end

        it "stores user site for later use" do
            output = flexmock
            status = flexmock
            output.should_receive(:read).and_return("/lib/python3/site-packages")
            status.should_receive("value.success?").and_return(true)
            flexmock(Open3).should_receive(:popen3)
                           .and_return([nil, output, nil, status])
                           .once

            package.python_path
            assert_equal File.join(prefix, "lib", "python3", "site-packages"),
                         package.python_path
        end
    end
end
