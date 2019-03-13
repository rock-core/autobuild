require 'autobuild/test'

class TestCVSImport < Minitest::Test
    include Autobuild

    attr_reader :cvsroot, :pkg_cvs

    def setup
        super
        Autobuild.logdir = "#{tempdir}/log"
        FileUtils.mkdir_p(Autobuild.logdir)
        @cvsroot = File.join(tempdir, 'cvsroot')
        @pkg_cvs = Package.new 'cvs'
        pkg_cvs.srcdir = File.join(tempdir, 'cvs')
    end

    def test_cvs
        untar('cvsroot.tar')
        importer = Autobuild.cvs(cvsroot, module: 'cvs')
        importer.import(pkg_cvs)
        assert File.exist?(File.join(pkg_cvs.srcdir, 'test'))
    end

    def test_update
        untar('cvsroot.tar')
        importer = Autobuild.cvs(cvsroot, module: 'cvs')
        importer.import(pkg_cvs)
        importer.import(pkg_cvs)
    end

    def test_update_fails_on_a_non_existent_directory
        untar('cvsroot.tar')
        importer = Autobuild.cvs(cvsroot, module: 'cvs')
        importer.import(pkg_cvs)
        FileUtils.rm_rf cvsroot
        assert_raises(Autobuild::SubcommandFailed) { importer.import pkg_cvs }
    end

    def test_checkout_fails_if_the_source_directory_is_not_a_cvs_repository
        FileUtils.mkdir_p cvsroot
        importer = Autobuild.cvs(cvsroot, module: 'cvs')
        assert_raises(Autobuild::SubcommandFailed) { importer.import pkg_cvs }
    end

    def test_update_fails_if_the_package_directory_is_not_a_cvs_repository
        untar 'cvsroot.tar'
        importer = Autobuild.cvs(cvsroot, module: 'cvs')
        FileUtils.mkdir_p pkg_cvs.srcdir
        assert_raises(Autobuild::ConfigException) { importer.import pkg_cvs }
    end

    def test_update_fails_if_the_package_directory_is_a_checkout_from_another_cvs_repository
        untar 'cvsroot.tar'
        FileUtils.cp_r cvsroot, "#{cvsroot}-dup"
        importer = Autobuild.cvs(cvsroot, module: 'cvs')
        importer.import(pkg_cvs)
        importer = Autobuild.cvs("#{cvsroot}-dup", module: 'cvs')
        assert_raises(Autobuild::ConfigException) { importer.import pkg_cvs }
    end
end
