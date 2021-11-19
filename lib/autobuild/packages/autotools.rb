require 'pathname'
require 'autobuild/timestamps'
require 'autobuild/environment'
require 'autobuild/package'
require 'autobuild/subcommand'
require 'shellwords'
require 'fileutils'

module Autobuild
    def self.autotools(opts, &proc)
        Autotools.new(opts, &proc)
    end

    Autobuild.programs['libtoolize'] = "glibtoolize" if Autobuild.macos?

    #
    # ==== Handles autotools-based packages
    #
    # == Used programs (see <tt>Autobuild.programs</tt>)
    # Autotools will use the 'aclocal', 'autoheader', 'autoconf', 'automake'
    # and 'bear' programs defined on Autobuild.programs. autoheader and bear
    # are disabled by default, aclocal, autoconf and automake use are
    # autodetected.
    #
    # To override this default behaviour on a per-package basis, use Autotools#use
    #
    class Autotools < Configurable
        attr_accessor :using, :configureflags, :aclocal_flags, :autoheader_flags,
                      :autoconf_flags, :automake_flags, :bear_flags

        @builddir = 'build'
        @@enable_bear_globally = false

        def self.enable_bear_globally?
            @@enable_bear_globally
        end

        def self.enable_bear_globally=(flag)
            @@enable_bear_globally = flag
        end

        def using_bear?
            return Autotools.enable_bear_globally? if using[:bear].nil?

            using[:bear]
        end

        def configurestamp
            "#{builddir}/config.status"
        end

        def initialize(options)
            @using = Hash.new
            @configureflags = []
            @aclocal_flags    = Array.new
            @autoheader_flags = Array.new
            @autoconf_flags   = Array.new
            @automake_flags   = Array.new
            @bear_flags       = ['-a']

            super
        end

        def common_utility_handling(utility, target)
            utility.task do
                progress_start "generating documentation for %s",
                               done_message: 'generated documentation for %s' do
                    if internal_doxygen_mode?
                        run_doxygen
                    else
                        run(utility.name,
                            Autobuild.tool(:make), "-j#{parallel_build_level}",
                            target, working_directory: builddir)
                    end
                    yield if block_given?
                end
            end
        end

        # Declare that the given target can be used to generate documentation
        def with_doc(target = 'doc', &block)
            common_utility_handling(doc_utility, target, &block)
        end

        def with_tests(target = 'test', &block)
            common_utility_handling(test_utility, target, &block)
        end

        # Overrides the default behaviour w.r.t. autotools script generation
        #
        # Use it like that:
        # * to force a generation step (skipping autodetection), do
        #     pkg.use <program> => true
        #   For instance, for aclocal
        #     pkg.use :aclocal => true
        #
        # * to force a generation step, overriding the program defined on Autobuild
        #     pkg.use <program> => true
        #   For instance, for autoconf
        #     pkg.use :autoconf => 'my_autoconf_program'
        #
        # * to disable a generation step, do
        #     pkg.use <program> => false
        #   For instance, for automake
        #     pkg.use :automake => false
        #
        # * to restore autodetection, do
        #     pkg.use <program> => nil
        #   For instance, for automake
        #     pkg.use :automake => nil
        #
        def use(*programs)
            programs =
                if programs.size == 1
                    programs.first
                else
                    programs
                end

            unless programs.kind_of?(Hash)
                programs = Array[*programs].each_with_object({}) do |spec, progs|
                    progs[spec.first] = spec.last
                end
            end
            programs.each do |name, opt|
                using[name.to_sym] = opt
            end

            nil
        end

        def prepare_for_forced_build
            super

            autodetect_needed_stages
            if using[:autoconf] || using[:autogen]
                FileUtils.rm_f File.join(srcdir, 'configure')
            end

            if using[:automake]
                Find.find(srcdir) do |path|
                    FileUtils.rm_f(path) if File.basename(path) == "Makefile.in"
                end
            end

            FileUtils.rm_f configurestamp
        end

        def import(**options)
            # We force a regen after the first checkout. The issue is that
            # autotools is less robust than it should, and very often it is
            # better to generate the build system for the system on which we
            # must build
            #
            # When we are doing a fresh checkout, a file is touched in the
            # source directory. That file is then deleted after #prepare gets
            # called
            is_checking_out = !File.directory?(srcdir)

            super
        ensure
            if is_checking_out && File.directory?(srcdir)
                FileUtils.touch File.join(srcdir, ".fresh_checkout")
            end
        end

        class UnexpectedConfigStatusOutput < RuntimeError; end

        def prepare
            super
            autodetect_needed_stages

            fresh_checkout_mark = File.join(srcdir, '.fresh_checkout')
            if File.file?(fresh_checkout_mark)
                prepare_for_forced_build
                FileUtils.rm_f fresh_checkout_mark
            end

            # Check if config.status has been generated with the
            # same options than the ones in configureflags
            #
            # If it is not the case, remove it to force reconfiguration
            if File.exist?(configurestamp)
                output = run('prepare', configurestamp, '--version').
                    grep(/with options/).first
                if output && (match = /with options "(.*)"/.match(output))
                    options = Shellwords.shellwords(match[1])
                else
                    raise UnexpectedConfigStatusOutput, "invalid output of "\
                        "config.status --version, expected a line with "\
                        "`with options \"OPTIONS\"`"
                end

                # Add the --prefix option to the configureflags array
                testflags = ["--prefix=#{prefix}"] + configureflags.flatten
                old_opt = options.find do |o|
                    if testflags.include?(o)
                        false
                    elsif o =~ /^-/
                        # Configuration option that is not specified, have to
                        # reconfigure
                        true
                    else
                        # This is an envvar entry. Ignore it if it is not
                        # explicitely given in configureflags
                        varname, = o.split("=").first
                        if (current_flag = testflags.find { |fl| fl =~ /^#{varname}=/ })
                            current_flag != o
                        else
                            false
                        end
                    end
                end
                new_opt = testflags.find { |o| !options.include?(o) }
                if old_opt || new_opt
                    if Autobuild.verbose
                        Autobuild.message "forcing reconfiguration of #{name} "\
                            "(#{old_opt} != #{new_opt})"
                    end
                    FileUtils.rm_f configurestamp # to force reconfiguration
                end
            end

            regen_target = create_regen_target
            file configurestamp => regen_target
        end

        def tool_program(tool)
            tool_flag = using[tool.to_sym]
            if tool_flag.respond_to?(:to_str)
                tool_flag.to_str
            else
                Autobuild.tool(tool)
            end
        end

        # If set to true, configure will be called with --no-create and
        # ./config.status will be started each time before "make"
        #
        # In general, you should not need that.
        attr_accessor :force_config_status

        private def autodetect_needed_stages
            # Autodetect autoconf/aclocal/automake
            #
            # Let the user disable the use of autoconf explicitely by using 'false'.
            # 'nil' means autodetection
            if using[:autoconf].nil?
                has_configure_in = %w[configure.in configure.ac].
                    any? { |p| File.file?(File.join(srcdir, p)) }
                using[:autoconf] = true if has_configure_in
            end
            using[:aclocal] = using[:autoconf] if using[:aclocal].nil?
            if using[:automake].nil?
                using[:automake] = File.exist?(File.join(srcdir, 'Makefile.am'))
            end

            if using[:libtool].nil?
                using[:libtool] = File.exist?(File.join(srcdir, 'ltmain.sh'))
            end

            if using[:autogen].nil?
                using[:autogen] = %w[autogen autogen.sh]
                    .find { |f| File.exist?(File.join(srcdir, f)) }
            end
        end

        # Adds a target to rebuild the autotools environment
        def create_regen_target(confsource = nil)
            conffile = "#{srcdir}/configure"
            if confsource
                file conffile => confsource
            elsif (confext = %w[.ac .in].find { |ext| File.exist?("#{conffile}#{ext}") })
                file conffile => "#{conffile}#{confext}"
            elsif using[:autoconf]
                raise PackageException.new(self, 'prepare'),
                      "neither configure.ac nor configure.in present in #{srcdir}"
            end

            file conffile do
                isolate_errors do
                    progress_start "generating autotools for %s",
                                   done_message: 'generated autotools for %s' do
                        regen
                    end
                end
            end

            conffile
        end

        def regen
            if using[:libtool]
                run 'configure', Autobuild.tool('libtoolize'), '--copy',
                    working_directory: srcdir
            end
            if using[:autogen]
                run 'configure', File.expand_path(using[:autogen], srcdir),
                    working_directory: srcdir
            else
                %i[aclocal autoconf autoheader automake].each do |tool|
                    next unless using[tool]

                    run 'configure', tool_program(tool), *send("#{tool}_flags"),
                        working_directory: srcdir
                end
            end
        end

        # Configure the builddir directory before starting make
        def configure
            super do
                command = ["#{srcdir}/configure"]
                command << "--no-create" if force_config_status
                command << "--prefix=#{prefix}"
                command += configureflags.flatten

                progress_start "configuring autotools for %s",
                               done_message: 'configured autotools for %s' do
                    run('configure', *command, working_directory: builddir)
                end
            end
        end

        # Do the build in builddir
        def build
            in_dir(builddir) do
                progress_start "building %s [progress not available]",
                               done_message: 'built %s' do
                    run('build', './config.status') if force_config_status

                    build_options = []
                    if using_bear?
                        build_tool = tool_program(:bear)
                        build_options = bear_flags
                        build_options << Autobuild.tool(:make)
                    else
                        build_tool = Autobuild.tool(:make)
                    end
                    build_options << "-j#{parallel_build_level}"

                    run('build', build_tool, *build_options)
                end
            end
            Autobuild.touch_stamp(buildstamp)
        end

        # Install the result in prefix
        def install
            in_dir(builddir) do
                progress_start "installing %s", :done_message => 'installed %s' do
                    run('install', Autobuild.tool(:make), 'install')
                end
            end

            super
        end
    end
end
