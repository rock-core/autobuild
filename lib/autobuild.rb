module Autobuild
    VERSION = "1.5.8" unless defined? Autobuild::VERSION
end

require 'autobuild/config'
require 'autobuild/configurable'
require 'autobuild/environment'
require 'autobuild/exceptions'
require 'autobuild/import/cvs'
require 'autobuild/import/darcs'
require 'autobuild/importer'
require 'autobuild/import/git'
require 'autobuild/import/svn'
require 'autobuild/import/archive'
require 'autobuild/import/tar'
require 'autobuild/packages/autotools'
require 'autobuild/packages/cmake'
require 'autobuild/packages/genom'
require 'autobuild/packages/import'
require 'autobuild/packages/orogen'
require 'autobuild/packages/pkgconfig'
require 'autobuild/packages/dummy'
require 'autobuild/pkgconfig'
require 'autobuild/reporting'
require 'autobuild/subcommand'
require 'autobuild/timestamps'

