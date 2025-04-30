require 'rake'

# rubocop:disable Style/MixinUsage
include Rake::DSL if defined?(Rake::DSL)
# rubocop:enable Style/MixinUsage

require 'utilrb/logger'

module Autobuild
    LIB_DIR = __dir__
    extend Logger::Root('Autobuild', Logger::INFO)
end

require 'socket'
require 'etc'
require 'find'
require 'pathname'
require 'shellwords'
require 'rake/tasklib'
require 'fileutils'
require 'optparse'
require 'singleton'
require 'open3'
require 'English'
require 'pastel'
require 'fcntl'
require 'rexml'
require 'tty-prompt'
require 'time'
require 'set'
require 'rbconfig'
require 'digest/sha1'
require 'open-uri'
require 'net/http'
require 'net/https'
require 'net/smtp'
require 'rubygems/version'

require "concurrent/atomic/atomic_boolean"
require "concurrent/array"

require 'utilrb/hash/map_value'
require 'utilrb/kernel/options'
require 'autobuild/tools'

require 'autobuild/version'
require 'autobuild/environment'
require 'autobuild/exceptions'
require 'autobuild/pkgconfig'
require 'autobuild/reporting'
require 'autobuild/mail_reporter'
require 'autobuild/subcommand'
require 'autobuild/timestamps'
require 'autobuild/parallel'
require 'autobuild/utility'
require 'autobuild/test_utility'
require 'autobuild/config'

require 'autobuild/importer'
require 'autobuild/import/cvs'
require 'autobuild/import/darcs'
require 'autobuild/import/git'
require 'autobuild/import/hg'
require 'autobuild/import/svn'
require 'autobuild/import/archive'
require 'autobuild/import/tar'

require 'autobuild/package'
require 'autobuild/configurable'
require 'autobuild/packages/autotools'
require 'autobuild/packages/gnumake'
require 'autobuild/packages/cmake'
require 'autobuild/packages/genom'
require 'autobuild/packages/import'
require 'autobuild/packages/orogen'
require 'autobuild/packages/pkgconfig'
require 'autobuild/packages/dummy'
require 'autobuild/packages/ruby'
require 'autobuild/packages/python'

require 'autobuild/rake_task_extension'
