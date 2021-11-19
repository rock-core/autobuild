module Autobuild
    # Control of the test facility for a package
    class TestUtility < Utility
        @coverage_enabled = false

        # Whether coverage is enabled for all tests
        def self.coverage_enabled?
            @coverage_enabled
        end

        # Enable code coverage for all tests
        def self.coverage_enabled=(flag)
            @coverage_enabled = flag
        end

        def initialize(name, package, install_on_error: true)
            super(name, package, install_on_error: install_on_error)
            @coverage_enabled = nil
            @coverage_source_dir = nil
            @coverage_target_dir = nil
        end

        # Whether code coverage should be generated for these tests
        def coverage_enabled?
            if @coverage_enabled.nil?
                TestUtility.coverage_enabled?
            else
                @coverage_enabled
            end
        end

        def coverage_available?
            @coverage_source_dir
        end

        # Controls whether code coverage should be measured
        #
        # @param [Boolean,nil] flag enable or disable code coverage. If set to
        #   nil, will use the default from {TestUtility.coverage?}
        attr_writer :coverage_enabled

        # Where the code coverage will be generated
        #
        # If left unset, {Utility#source_dir} will be used instead. Relative
        # paths are resolved relative to {Package#builddir}
        attr_writer :coverage_source_dir

        # The full path to the coverage information
        #
        # It cannot be a subdirectory of {#source_dir}
        #
        # @return [String]
        def coverage_source_dir
            if @coverage_source_dir
                relative = if package.respond_to?(:builddir)
                               package.builddir
                           else
                               package.srcdir
                           end
                File.expand_path(@coverage_source_dir, relative)
            end
        end

        # Where the code coverage will be generated
        #
        # If left unset, {Utility#target_dir}/coverage will be used instead.
        # Relative paths are resolved relative to {Package#prefix}
        attr_writer :coverage_target_dir

        # Where the coverage information should be installed
        #
        # It is the same than {Utility#target_dir}/coverage by default
        #
        # @return [String]
        def coverage_target_dir
            if @coverage_target_dir
                File.expand_path(@coverage_target_dir, package.prefix)
            elsif (target_dir = self.target_dir)
                File.join(target_dir, 'coverage')
            end
        end

        def install
            super

            if !coverage_enabled?
                return
            elsif !coverage_available?
                package.warn "%s: #coverage_source_dir not set on #test_utility, "\
                    "skipping installation of the code coverage results"
            end

            coverage_target_dir  = self.coverage_target_dir
            coverage_source_dir  = self.coverage_source_dir
            if "#{coverage_source_dir}/".start_with?("#{source_dir}/")
                raise ArgumentError, "#coverage_source_dir cannot be a subdirectory "\
                    "of #source_dir in #{package.name}"
            elsif target_dir == coverage_target_dir
                raise ArgumentError, "#coverage_target_dir cannot be the same than of "\
                    "#target_dir in #{package.name}"
            end

            FileUtils.mkdir_p File.dirname(coverage_target_dir)
            FileUtils.cp_r coverage_source_dir, coverage_target_dir
            package.message "%s: copied test coverage results for #{package.name} from "\
                "#{coverage_source_dir} to #{coverage_target_dir}"
        end
    end
end
