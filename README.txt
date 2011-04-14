Copyright (c) 2006-2011 Sylvain Joyeux <sylvain.joyeux@m4x.org> and contributors

* http://rock-robotics.org

This work is licensed under the GPLv2 license. See License.txt for details

== What's autobuild ?
Autobuild imports, configures, builds and installs various kinds of software packages.
It can be used in software development to make sure that nothing is broken in the 
build process of a set of packages, or can be used as an automated installation tool.

Autobuild config files are Ruby scripts which configure rake to
* imports the package from a SCM or (optionnaly) updates it
* configures it. This phase can handle code generation, configuration (for
  instance for autotools-based packages), ...
* build
* install

It takes the dependencies between packages into account in its build process,
updates the needed environment variables (+PKG_CONFIG_PATH+, +PATH+,
+LD_LIBRARY_PATH+, ...)


== WARNING for 0.5 users
Old configuration files used with autobuild 0.5 aren't accepted by Autobuild
0.6. Since 0.6, Autobuild uses Ruby for configuration (just like rake does)

== Available packages
=== Common usage
All package objects define the following attributes
*importer*:: the importer object (see "Available importers" below)
*srcdir*:: where the package sources are located. If it is a relative
	   path, it is relative to the value of Autobuild.srcdir. The default is to
	   use the package name. 
*prefix*:: the directory where the package should be installed. If it is a relative
	   path, it is relative to the value of Autobuild.prefix. The default is to
	   use the package name. 

Each package method (Autobuild.import, Autobuild.autotools, ...) takes either a package
name for first argument, or a <tt>name => dependency_array</tt> hash, and take a block which
can be used to configure the package. For instance
    Autobuild.import :my_package do |pkg|
	pkg.srcdir = 'my_package_dir'
    end

    Autobuild.import :my_package => [:depends, :depends_also] do |pkg|
    end

=== Source only
    package = Autobuild.import(dependencies) do |pkg|
	<package configuration>
    end

Use +import+ if you need the package sources but don't need to build it. You just need
to set +importer+ and +srcdir+. +prefix+ is ignored.

=== Autotools
    package = Autobuild.autotools(name, dependencies) do |pkg|
	<package configuration>
    end

Use this to build GNU autotools-based packages. This handles autoconf-only packages as 
well as those using automake

Options to give the +configure+ script are given in the +configureflags+ array
    pkg.configureflags = ['--with-blah', 'FOO=bar' ]

If you want the files produced during the build to be separated from the source files, set the +builddir+ attribute.
For now, it has to be a relative path, relative to the source directory.
    pkg.builddir = 'build'

The generation of the configure script uses four programs: +autoheader+, +autoconf+, +aclocal+, 
+automake+. The default program path can be overriden in the Autotools.programs hash. For
instance, to be sure that <tt>automake-1.9</tt> is used <bb>for all packages</bb>, you set

    Autotools.programs['automake'] = 'automake-1.9'

Autobuild tries to detect what tools it should run, but you can override. Autodetection works
as follows:
* if a script named +autogen+ or +autogen.sh+ exists in the package source directory, it is run
  and the other tools are not. The name of this kind of script can be set by calling Autotools#use
    pkg.use :autogen => 'my_autogen_script'
* +autoheader+ is never used by default
* +autoconf+ is used if there is <tt>configure.ac</tt> or <tt>configure.in</tt> in the source dir
* +aclocal+ is used if +autoconf+ is enabled (either explicitely or by autodetection)
* +automake+ is used if there is a <tt>Makefile.am</tt> file in the source dir
* you can force to enable or disable any of these steps by calling Autotools#use. Set it to +true+
  to force its usage, +false+ to disable it or to a string to force the usage of a particular program
    pkg.use :autogen => false
    pkg.use :automake => false
    pkg.use :autoheader => true
    pkg.use :autoconf => 'my_autoconf_program'

  The 'autogen' option cannot be set to +true+.

The only program used during the build and install phases is +make+. Its path can be overriden 
in the Autobuild.programs hash
    Autobuild.programs['make'] = 'gnumake'

=== CMake

A cmake package is defined with
 
  require 'autobuild/packages/cmake'
  Autobuild.cmake :package_name do |pkg|
    <package configuration> ...
  end

The only configuration attribute available for CMake package is:
+builddir+ 
  the directory in which to configure and build the package. It is relative to
  the package sources. A global value can be defined through Autobuild::CMake.builddir

Additionally, the #define(name, value) method allows to define configuration variables.

== Available importers
You must set an importer object for each package. The package importer is the +importer+ attribute
and is set via <tt>package.importer = my_importer</tt>. An importer +foo+ is defined by the class
Autobuild::FooImporter and defines a Autobuild.foo method which creates a new importer object.
Importer classes files are in <tt>lib/autobuild/import/</tt>

=== Tar
    package.importer = tar(uri[, options])
    
Downloads a tarfile at +uri+ and saves it into a local cache directory.
The cache directory can be set in the +options+ hash
    package.importer = tar(uri, :cachedir = '/tmp')

It is "#{Autobuild.prefix}/cache" by default. The known URI schemes are file://
for local files and http:// or ftp:// for remote files.  There is currently no
way to set passive mode on FTP, since the standard open-uri library does not
allow that.

=== CVS 
    package.importer = cvs(cvsroot, module[, options])

Where +options+ is an option hash. See also Autobuild::CVSImporter and Autobuild.cvs

* the default CVS command is +cvs+. It can be changed by
    Autobuild.programs['cvs'] = 'my_cvs_command'
* the default checkout option is <tt>-P</tt>. You can change that by giving a +cvsco+ option
    cvs cvsroot, module, :cvsco => ['--my', '--cvs', '--options']
* the default update option is <tt>-dP</tt>. You can change that by giving a +cvsup+ option
    cvs cvsroot, module, :cvsup => ['--my', '--cvs', '--options']

=== Subversion
    package.importer = svn(url[, options])

Where +options+ is an option hash. See also Autobuild::SVNImporter and Autobuild.svn

* the default Subversion command is +svn+. It can be changed by
    Autobuild.programs['svn'] = 'my_svn_command'
* by default, no options are given to checkout. You add some by giving a +svnco+ option
    svn url, :svnco => ['--my', '--svn', '--options']
* by default, no options are given to update. You can add some by giving a +svnup+ option
    svn url, :svnup => ['--my', '--svn', '--options']

=== Darcs
    package.importer = darcs(url[, options])

Where +options+ is a hash. See also Autobuild::DarcsImporter and Autobuild.darcs

* the default Darcs command is +darcs+. It can be changed by
    Autobuild.programs['darcs'] = 'my_svn_command'
* by default, no options are given to get. You add some by giving a +get+ option
    darcs url, :get => ['--my', '--darcs', '--options']
* by default, no options are given to pull. You can add some by giving a +pull+ option
    darcs url, :pull => ['--my', '--darcs', '--options']

=== Git
    package.importer = git(url[, branch])

Imports the given branch (or master if none is given) of the repository at the
given URL. The branch is imported as the 'autobuild' remote and fetched into
the master local branch.

= Copyright and license
Author::    Sylvain Joyeux <sylvain.joyeux@m4x.org>
Copyright:: Copyright (c) 2005-2008 Sylvain Joyeux
License::   GPL

