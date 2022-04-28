require 'autobuild/configurable'
require 'autobuild/packages/gnumake'

module Autobuild
    def self.cmake(options, &block)
        CMake.new(options, &block)
    end

    # Handler class to build CMake-based packages
    class CMake < Configurable
        class << self
            def builddir
                @builddir || Configurable.builddir
            end

            def builddir=(new)
                if Pathname.new(new).absolute?
                    raise ConfigException, "absolute builddirs are not supported"
                end
                if new.nil? || new.empty?
                    raise ConfigException, "builddir must be non-nil and non-empty"
                end

                @builddir = new
            end

            attr_writer :full_reconfigures

            def full_reconfigures?
                @full_reconfigures
            end

            # Global default for the CMake generator to use. If nil (the
            # default), the -G option will not be given at all. Will work only
            # if the generator creates makefiles
            #
            # It can be overriden on a per-package basis with CMake.generator=
            attr_accessor :generator

            attr_reader :prefix_path, :module_path

            # Whether files that are not within CMake's install manifest but are
            # present in the prefix should be deleted. Note that the contents of
            # {#log_dir} are unaffected.
            #
            # It is false by default. Set to true only if each package has its
            # own prefix.
            def delete_obsolete_files_in_prefix?
                @@delete_obsolete_files_in_prefix
            end

            # Set {#delete_obsolete_files_in_prefix?}
            def delete_obsolete_files_in_prefix=(flag)
                @@delete_obsolete_files_in_prefix = flag
            end

            @@delete_obsolete_files_in_prefix = false
        end
        @builddir = nil
        @prefix_path = []
        @module_path = []
        @full_reconfigures = true

        # a key => value association of defines for CMake
        attr_reader :defines

        # The list of all -D options that should be passed on to CMake
        def all_defines
            additional_defines = Hash[
                "CMAKE_INSTALL_PREFIX" => prefix,
                "CMAKE_MODULE_PATH" => module_path.join(";"),
                "CMAKE_PREFIX_PATH" => prefix_path.join(";")]
            self.class.defines.merge(additional_defines).merge(defines)
        end

        # If true, always run cmake before make during the build
        attr_accessor :always_reconfigure
        # If true, we always remove the CMake cache before reconfiguring.
        #
        # See #full_reconfigures? for more details
        attr_writer :full_reconfigures
        # Sets a generator explicitely for this component. See #generator and
        # CMake.generator
        attr_writer :generator

        # The CMake generator to use. You must choose one that generates
        # Makefiles. If not set for this package explicitely, it is using the
        # global value CMake.generator.
        def generator
            @generator || CMake.generator
        end

        # If true, we always remove the CMake cache before reconfiguring. This
        # is to workaround the aggressive caching behaviour of CMake, and is set
        # to true by default.
        #
        # See CMake.full_reconfigures? and CMake.full_reconfigures= for a global
        # setting
        def full_reconfigures?
            if @full_reconfigures.nil?
                CMake.full_reconfigures?
            else
                @full_reconfigures
            end
        end

        def cmake_cache
            File.join(builddir, "CMakeCache.txt")
        end

        def configurestamp
            cmake_cache
        end

        def initialize(options)
            @defines = Hash.new
            super
            @delete_obsolete_files_in_prefix = self.class.
                delete_obsolete_files_in_prefix?
        end

        # (see CMake.delete_obsolete_files_in_prefix?)
        def delete_obsolete_files_in_prefix?
            @delete_obsolete_files_in_prefix
        end

        # (see CMake.delete_obsolete_files_in_prefix=)
        attr_writer :delete_obsolete_files_in_prefix

        @@defines = Hash.new

        def self.defines
            @@defines
        end

        def self.define(name, value)
            @@defines[name] =
                if value.respond_to?(:to_str)
                    value.to_str
                elsif value
                    'ON'
                else
                    'OFF'
                end
        end

        def define(name, value)
            @defines[name] =
                if value.respond_to?(:to_str)
                    value.to_str
                elsif value
                    'ON'
                else
                    'OFF'
                end
        end

        DOXYGEN_ACCEPTED_VARIABLES = {
            '@CMAKE_SOURCE_DIR@' => ->(pkg) { pkg.srcdir },
            '@PROJECT_SOURCE_DIR@' => ->(pkg) { pkg.srcdir },
            '@CMAKE_BINARY_DIR@' => ->(pkg) { pkg.builddir },
            '@PROJECT_BINARY_DIR@' => ->(pkg) { pkg.builddir },
            '@PROJECT_NAME@' => ->(pkg) { pkg.name }
        }.freeze

        class << self
            # Flag controlling whether autobuild should run doxygen itself or
            # use the "doc" target generated by CMake
            #
            # This is experimental and OFF by default. See CMake#run_doxygen for
            # more details
            #
            # See also CMake#always_use_doc_target= and CMake#always_use_doc_target?
            # for a per-package control of that feature
            attr_writer :always_use_doc_target

            # Flag controlling whether autobuild should run doxygen itself or
            # use the "doc" target generated by CMake
            #
            # This is experimental and OFF by default. See CMake#run_doxygen for
            # more details
            #
            # See also CMake#always_use_doc_target= and CMake#always_use_doc_target?
            # for a per-package control of that feature
            def always_use_doc_target?
                @always_use_doc_target
            end
        end
        @always_use_doc_target = true

        # Flag controlling whether autobuild should run doxygen itself or
        # use the "doc" target generated by CMake
        #
        # This is experimental and OFF by default. See CMake#run_doxygen for
        # more details
        #
        # See also CMake.always_use_doc_target= and CMake.always_use_doc_target?
        # for a global control of that feature
        attr_reader :always_use_doc_target

        # Flag controlling whether autobuild should run doxygen itself or
        # use the "doc" target generated by CMake
        #
        # This is experimental and OFF by default. See CMake#run_doxygen for
        # more details
        #
        # See also CMake.always_use_doc_target= and CMake.always_use_doc_target?
        # for a global control of that feature
        def always_use_doc_target?
            if @always_use_doc_target.nil?
                CMake.always_use_doc_target?
            else
                @always_use_doc_target
            end
        end

        # To avoid having to build packages to run the documentation target, we
        # try to autodetect whether (1) the package is using doxygen and (2)
        # whether the cmake variables in the doxyfile can be provided by
        # autobuild itself.
        #
        # This can be disabled globally by setting
        # Autobuild::CMake.always_use_doc_target= or on a per-package basis with
        # #always_use_doc_target=
        #
        # This method returns true if the package can use the internal doxygen
        # mode and false otherwise
        def internal_doxygen_mode?
            return false if always_use_doc_target?

            doxyfile_in = File.join(srcdir, "Doxyfile.in")
            return false unless File.file?(doxyfile_in)

            File.readlines(doxyfile_in).each do |line|
                matches = line.scan(/@[^@]+@/)
                if matches.any? { |str| !DOXYGEN_ACCEPTED_VARIABLES.key?(str) }
                    return false
                end
            end
        end

        # To avoid having to build packages to run the documentation target, we
        # try to autodetect whether (1) the package is using doxygen and (2)
        # whether the cmake variables in the doxyfile can be provided by
        # autobuild itself.
        #
        # This can be disabled globally by setting
        # Autobuild::CMake.always_use_doc_target or on a per-package basis with
        # #always_use_doc_target
        #
        # This method generates the corresponding doxygen file in
        # <builddir>/Doxygen and runs doxygen. It raises if the internal doxygen
        # support cannot be used on this package
        def run_doxygen
            doxyfile_in = File.join(srcdir, "Doxyfile.in")
            unless File.file?(doxyfile_in)
                raise "no Doxyfile.in in this package, "\
                    "cannot use the internal doxygen support"
            end
            doxyfile_data = File.readlines(doxyfile_in).map do |line|
                line.gsub(/@[^@]+@/) do |match|
                    DOXYGEN_ACCEPTED_VARIABLES[match].call(self)
                end
            end
            doxyfile = File.join(builddir, "Doxyfile")
            File.open(doxyfile, 'w') do |io|
                io.write(doxyfile_data)
            end
            run('doc', Autobuild.tool(:doxygen), doxyfile)
        end

        def common_utility_handling( # rubocop:disable Metrics/ParameterLists
            utility,
            target,
            *args,
            start_msg,
            done_msg,
            post_process: nil
        )
            utility.source_ref_dir = builddir
            utility.task do
                progress_start start_msg, :done_message => done_msg do
                    if internal_doxygen_mode?
                        run_doxygen
                    else
                        run(utility.name,
                            Autobuild.tool(:make),
                            "-j#{parallel_build_level}",
                            target, *args,
                            working_directory: builddir)
                    end
                    yield if block_given?
                end

                post_process&.call
            end
        end

        def with_coverage(&block)
            @with_coverage ||= block
        end

        def coverage_block
            proc do
                next unless test_utility.coverage_enabled?
                next unless @with_coverage

                progress_start "generating coverage report for %s",
                               done_message: "generated coverage report for %s" do
                    @with_coverage.call
                end
            end
        end

        # Declare that the given target can be used to generate documentation
        def with_doc(target = 'doc', &block)
            common_utility_handling(
                doc_utility, target,
                "generating documentation for %s",
                "generated documentation for %s", &block)
        end

        def with_tests(target = 'test', &block)
            common_utility_handling(
                test_utility, target, "ARGS=-V",
                "running tests for %s",
                "successfully ran tests for %s",
                post_process: coverage_block, &block)
        end

        CMAKE_EQVS = {
            'ON' => 'ON',
            'YES' => 'ON',
            'OFF' => 'OFF',
            'NO' => 'OFF'
        }.freeze
        def equivalent_option_value?(old, new)
            if old == new
                true
            else
                old = CMAKE_EQVS[old]
                new = CMAKE_EQVS[new]
                if old && new
                    old == new
                else
                    false
                end
            end
        end

        def import(**options)
            super

            Dir.glob(File.join(srcdir, "*.pc.in")) do |file|
                file = File.basename(file, ".pc.in")
                provides "pkgconfig/#{file}"
            end
        end

        def module_path
            CMake.module_path
        end

        def prefix_path
            seen = Set.new
            result = Array.new

            raw = (dependencies.map { |pkg_name| Autobuild::Package[pkg_name].prefix } +
                CMake.prefix_path)
            raw.each do |path|
                unless seen.include?(path)
                    seen << path
                    result << path
                end
            end
            result
        end

        def update_environment
            super
            prefix_path.each do |p|
                env_add_path 'CMAKE_PREFIX_PATH', p
            end
        end

        def defines_changed?(all_defines, cache_data)
            all_defines.any? do |name, value|
                if (match = /^#{name}:\w+=(.*)$/.match(cache_data))
                    old_value = match[1]
                end

                value = value.to_s
                if !old_value || !equivalent_option_value?(old_value, value)
                    if Autobuild.debug
                        message "%s: option '#{name}' changed value: "\
                            "'#{old_value}' => '#{value}'"
                    end

                    if old_value
                        message "%s: changed value of #{name} "\
                            "from #{old_value} to #{value}"
                    else
                        message "%s: setting value of #{name} to #{value}"
                    end

                    true
                end
            end
        end

        def prepare
            # A failed initial CMake configuration leaves a CMakeCache.txt file,
            # but no Makefile.
            #
            # Delete the CMakeCache to force reconfiguration
            unless File.exist?(File.join(builddir, 'Makefile'))
                FileUtils.rm_f(cmake_cache)
            end

            doc_utility.source_ref_dir = builddir

            if File.exist?(cmake_cache)
                cache = File.read(cmake_cache)
                if defines_changed?(all_defines, cache)
                    if Autobuild.debug
                        message "%s: CMake configuration changed, forcing a reconfigure"
                    end
                    FileUtils.rm_f cmake_cache
                end
            end

            super
        end

        # Configure the builddir directory before starting make
        def configure
            super do
                in_dir(builddir) do
                    unless File.file?(File.join(srcdir, 'CMakeLists.txt'))
                        raise ConfigException.new(self, 'configure'),
                              "#{srcdir} contains no CMakeLists.txt file"
                    end

                    command = ["cmake"]

                    if Autobuild.windows?
                        command << '-G'
                        command << "MSYS Makefiles"
                    end

                    all_defines.each do |name, value|
                        command << "-D#{name}=#{value}"
                    end
                    command << Array(generator).map { |g| "-G#{g}" } if generator
                    command << srcdir

                    progress_start "configuring CMake for %s",
                                   done_message: "configured CMake for %s" do
                        FileUtils.rm_f cmake_cache if full_reconfigures?
                        run('configure', *command)
                    end
                end
            end
        end

        def show_make_messages?
            if !@show_make_messages.nil?
                @show_make_messages
            else
                CMake.show_make_messages?
            end
        end

        attr_writer :show_make_messages

        def self.show_make_messages?
            @show_make_messages
        end

        def self.show_make_messages=(value)
            @show_make_messages = value
        end

        # Do the build in builddir
        def build
            current_message = +""
            in_dir(builddir) do
                progress_start "building %s" do
                    if always_reconfigure || !File.file?('Makefile')
                        run('build', Autobuild.tool(:cmake), '.')
                    end

                    warning_count = 0
                    Autobuild.make_subcommand(self, 'build') do |line|
                        needs_display = false
                        if line =~ /\[\s*(\d+)%\]/
                            progress "building %s (#{Integer($1)}%)"
                        elsif line !~ /^(?:Generating|Linking|Scanning|Building|Built)/
                            warning_count += 1 if line =~ /warning/
                            if show_make_messages?
                                current_message += line + "\n"
                                needs_display = true
                            end
                        end
                        if !needs_display && !current_message.empty?
                            current_message.split("\n").each do |l|
                                message "%s: #{l}", :magenta
                            end
                            current_message.clear
                        end
                    end
                    current_message.split("\n").each do |l|
                        message "%s: #{l}", :magenta
                    end
                    if warning_count > 0
                        msg_warning = Autoproj.color("(#{warning_count} warnings)", :bold)
                        progress_done "built %s #{msg_warning}"
                    else
                        progress_done "built %s"
                    end
                end
            end
            Autobuild.touch_stamp(buildstamp)
        rescue ::Exception
            current_message.split("\n").each do |l|
                message "%s: #{l}", :magenta
            end
            raise
        end

        # Install the result in prefix
        #
        # If {#delete_obsolete_files_in_prefix?} is set, files that are present
        # in the prefix but not in CMake's install manifest will be removed.
        def install
            in_dir(builddir) do
                progress_start "installing %s", done_message: 'installed %s' do
                    run('install', Autobuild.tool(:make),
                        "-j#{parallel_build_level}", 'install')
                end

                delete_obsolete_files if delete_obsolete_files_in_prefix?
            end
            super
        end

        # @api private
        #
        # Delete files in {#prefix} that are not present in CMake's install
        # manifest
        #
        # This is enabled globally by {CMake.delete_obsolete_files_in_prefix=} or
        # per-package with {#delete_obsolete_files_in_prefix=}. Do NOT enable if packages
        # share the same prefix.
        def delete_obsolete_files
            # The expand_path is required to sanitize the paths, which can
            # contain e.g. double //
            cmake_install_manifest = File.join(builddir, 'install_manifest.txt')
            manifest_contents = File.readlines(cmake_install_manifest).
                map { |p| File.expand_path(p.chomp) }.to_set
            logdir = self.logdir
            counter = 0
            Find.find(prefix) do |path|
                Find.prune if path == logdir
                if !manifest_contents.include?(path) && File.file?(path)
                    counter += 1
                    FileUtils.rm path
                end
            end
            if counter > 0
                message "%s: removed #{counter} obsolete files from prefix (cmake)"
            end
        end

        def self_fingerprint
            return unless (base = super)

            all_defines = self.class.defines.merge(defines).sort_by(&:first)
            Digest::SHA1.hexdigest(base + all_defines.join(""))
        end
    end
end
