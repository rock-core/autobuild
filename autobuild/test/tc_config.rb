require 'test/unit'
require 'stringio'
require 'autobuild/options'
require 'autobuild/config'

class TC_Config < Test::Unit::TestCase
CONFIG_FILE = <<EOF
defines:
    global_prefix: /home/sjoyeux/openrobots
    platform: B21R
    buildname: i386-linux
    mail: sjoyeux@laas.fr

    srcdir: ${global_prefix}/robots/$platform
    prefix: ${global_prefix}/$buildname/robots/$platform

repositories:
    - &openrobots ':ext:sjoyeux@cvs.laas.fr/cvs/openrobots'
    - &sjoyeux 'svn+ssh://sjoyeux@pollux.laas.fr/home/sjoyeux/svnroot'
    - &sjoyeux_openrobots 'svn+ssh://sjoyeux@pollux.laas.fr/home/sjoyeux/svnroot-openrobots'
    - &fpy ':ext:sjoyeux@pollux.laas.fr/home/fpy/RIA/CVSDIR'

autobuild-config:
    srcdir: $srcdir
    prefix: $prefix
    clean-log: true
    nice: 0

    mail:
        to: $mail

    environment:
        PATH: [ /bin, /usr/bin, $global_prefix/$buildname/tools/bin ]
        PKG_CONFIG_PATH: $global_prefix/$buildname/tools/lib/pkgconfig
        LD_LIBRARY_PATH:

programs:
    aclocal: aclocal-1.9
EOF
    def setup
        @options = StringIO.open(CONFIG_FILE) { |f| Config.load(f, Options.default) }
    end

    def test_nice_type
        assert_equal(0, $NICE)
        assert_kind_of(Fixnum, $NICE)
    end
end

