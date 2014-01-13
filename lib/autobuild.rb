require 'rake'

if defined? Rake::DSL
    include Rake::DSL
end

module Autobuild
end

begin
    require 'rmail'
    require 'rmail/serialize'
    Autobuild::HAS_RMAIL = true
rescue LoadError
    Autobuild::HAS_RMAIL = false
end

require 'net/smtp'
require 'socket'
require 'etc'
require 'find'
require 'thread'
require 'pathname'
require 'shellwords'
require 'find'
require 'rake/tasklib'
require 'fileutils'

require 'autobuild/version'
require 'autobuild/environment'
require 'autobuild/exceptions'
require 'autobuild/pkgconfig'
require 'autobuild/reporting'
require 'autobuild/subcommand'
require 'autobuild/timestamps'
require 'autobuild/parallel'
require 'autobuild/utility'
require 'autobuild/config'

require 'autobuild/importer'
require 'autobuild/import/cvs'
require 'autobuild/import/darcs'
require 'autobuild/importer'
require 'autobuild/import/git'
require 'autobuild/import/hg'
require 'autobuild/import/svn'
require 'autobuild/import/archive'
require 'autobuild/import/tar'

require 'autobuild/package'
require 'autobuild/configurable'
require 'autobuild/packages/autotools'
require 'autobuild/packages/cmake'
require 'autobuild/packages/genom'
require 'autobuild/packages/import'
require 'autobuild/packages/orogen'
require 'autobuild/packages/pkgconfig'
require 'autobuild/packages/dummy'
require 'autobuild/packages/ruby'

require 'autobuild/rake_task_extension'

