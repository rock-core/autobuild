# This sample file installs a set of autotools packages from
# the OpenRobots suite of tools (http://softs.laas.fr/openrobots)
#
# This version uses the Tar importer to get the latest release
require 'autobuild'
require 'autobuild/packages/autotools'
require 'autobuild/import/tar'

Thread.abort_on_exception = true
STDOUT.sync = true

# Ask the user (you) where you want everything installed
default_prefix = "#{ENV['HOME']}/openrobots"
print "Where to intall openrobots ? [#{default_prefix}]"
answer = STDIN.readline
answer = default_prefix if answer == "\n"

# Set the root directory for sources import and package installation
Autobuild.srcdir = File.join(answer, "src")
Autobuild.prefix = answer

# Define a fake 'openrobots' package type which describes the common package
# configuration for packages from openrobots
#
# spec is either a name (the package name) or a name => dependencies hash
OPENROBOTS_DOWNLOAD_BASEURL = "http://softs.laas.fr/openrobots/php/download.php/"
def openrobots(version, spec)
    Autobuild.autotools(spec) do |pkg|
	# Install the sources in #{Autobuild.srcdir}/package_name
	pkg.srcdir   = pkg.name

	# Build packages into #{package source dir}/build
	pkg.builddir = "build"

	# The importer object will download the file and decompress it into the
	# specified source directory
	#
	# The tarballs contain a name-version directory. The :tardir option
	# makes the tar importer rename that directory into 'name'
	pkg.importer = Autobuild.tar(OPENROBOTS_DOWNLOAD_BASEURL + "#{pkg.name}-#{version}.tar.gz", 
				     :tardir => "#{pkg.name}-#{version}")
				     
	# Do not autogenerate configure scripts, use the ones in the tarball instead
	pkg.use :aclocal => false
	pkg.use :autoconf => false
	pkg.use :automake => false

	# All openrobots package depend on mkdep
	if pkg.name != "mkdep"
	    pkg.depends_on 'mkdep'
	end
    end
end

# You can override the version of aclocal/autoconf/automake used if needed
# Autotools.aclocal  = "aclocal-1.9"
# Autotools.automake = "automake-1.9"
    
# Declare the packages themselves
openrobots "2.6", :mkdep
openrobots "2.2", :pocolibs

# Genom depends on pocolibs, declare that
openrobots "1.99.902", :genom => :pocolibs

# GDHE needs a X display to install. Check that the DISPLAY environment
# variable is set
if ENV['DISPLAY']
    openrobots "3.7", :gdhe
else
    STDERR.puts "GDHE installation requires a X display. Disabled"
end

