# Rakefile for Autobuild
# Copyright 2005 by Sylvain Joyeux (sylvain.joyeux@m4x.org)

# Based on the Rakefile for MetaProject
# Copyright 2005 by Aslak Hellesoy (aslak.hellesoy@gmail.org)
# All rights reserved.

# This file is may be distributed under an MIT style license.  See
# MIT-LICENSE for details.

$:.unshift('lib')
require 'meta_project'
require 'rake/gempackagetask'
require 'rake/contrib/rubyforgepublisher'
require 'rake/contrib/xforge'
require 'rake/clean'
require 'rake/testtask'
require 'rake/rdoctask'

# Versioning scheme: MAJOR.MINOR.PATCH
# MAJOR bumps when API is broken backwards
# MINOR bumps when the API is broken backwards in a very slight/subtle (but not fatal) way
# -OR when a new release is made and propaganda is sent out.
# PATCH is bumped for every API addition and/or bugfix (ideally for every commit)
# Later DamageControl can bump PATCH automatically.
#
# REMEMBER TO KEEP PKG_VERSION IN SYNC WITH THE CHANGES FILE!
PKG_NAME = "autobuild"
PKG_VERSION = "0.5.1"
PKG_FILE_NAME = "#{PKG_NAME}-#{PKG_VERSION}"
PKG_FILES = FileList[
  'bin/*',
  '[A-Z]*',
  'lib/**/*.rb', 
  'doc/**/*'
]

task :default => [:gem]

# Create a task to build the RDOC documentation tree.
rd = Rake::RDocTask.new("rdoc") do |rdoc|
  rdoc.rdoc_dir = 'html'
#  rdoc.template = 'kilmer'
#  rdoc.template = 'css2'
#  rdoc.template = 'doc/jamis.rb'
  rdoc.title    = "Autobuild"
  rdoc.options << '--main' << 'README'
  rdoc.rdoc_files.include('README', 'CHANGES')
  rdoc.rdoc_files.include('lib/**/*.rb', 'doc/**/*.rdoc')
  rdoc.rdoc_files.exclude('doc/**/*_attrs.rdoc')
end

# ====================================================================
# Create a task that will package the Rake software into distributable
# tar, zip and gem files.

spec = Gem::Specification.new do |s|
  
  #### Basic information.

  s.name = PKG_NAME
  s.version = PKG_VERSION
  s.summary = 'Rake-based utility to build and install multiple packages with dependencies'
  s.description = <<EOF
Autobuild imports, configures, builds and installs various kinds of software packages.
It can be used in software development to make sure that nothing is broken in the 
build process of a set of packages, or can be used as an automated installation tool.
EOF

  s.files = PKG_FILES.to_a
  s.require_path = 'lib'

  #### Documentation and testing.

  s.has_rdoc = true
  s.extra_rdoc_files = rd.rdoc_files.reject { |fn| fn =~ /\.rb$/ }.to_a
  s.rdoc_options <<
    '--title' <<  'Autobuild' <<
    '--main' << 'README'

  #### Author and project details.

  s.author = "Sylvain Joyeux"
  s.email = "sylvain.joyeux@m4x.org"
  s.homepage = "http://autobuild.rubyforge.org"
  s.rubyforge_project = "autobuild"
end

# Fix 1.8.4 - 1.8.3 issue
class << spec
    def to_yaml
        out = super 
        out = '--- ' + out unless out =~ /^---/ 
        out 
    end
end

desc "Build Gem"
Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_zip = true
  pkg.need_tar = true
end

# Support Tasks ------------------------------------------------------

desc "Look for TODO and FIXME tags in the code"
task :todo do
  Pathname.new(File.dirname(__FILE__)).egrep(/#.*(FIXME|TODO|TBD|DEPRECATED)/) do |match|
    puts match
  end
end

task :release => [:verify_env_vars, :release_files, :publish_doc, :tag] # :publish_news, 

task :verify_env_vars do
  raise "RUBYFORGE_USER environment variable not set!" unless ENV['RUBYFORGE_USER']
  raise "RUBYFORGE_PASSWORD environment variable not set!" unless ENV['RUBYFORGE_PASSWORD']
end

task :publish_doc do
  publisher = Rake::RubyForgePublisher.new('xforge', ENV['RUBYFORGE_USER'])
  publisher.upload
end

desc "Release files on RubyForge"
task :release_files => [:gem] do
  release_files = FileList[
    "pkg/#{PKG_FILE_NAME}.gem"
  ]

  Rake::XForge::Release.new(MetaProject::Project::XForge::RubyForge.new('xforge')) do |release|
    # Never hardcode user name and password in the Rakefile!
    release.user_name = ENV['RUBYFORGE_USER']
    release.password = ENV['RUBYFORGE_PASSWORD']
    release.files = release_files.to_a
    release.release_name = "Autobuild #{PKG_VERSION}"
    # The rest of the options are defaults (among others, release_notes and release_changes, parsed from CHANGES)
  end
end

desc "Publish news on RubyForge"
task :publish_news => [:gem] do
  release_files = FileList[
    "pkg/#{PKG_FILE_NAME}.gem"
  ]

  Rake::XForge::NewsPublisher.new(MetaProject::Project::XForge::RubyForge.new('xforge')) do |news|
    # Never hardcode user name and password in the Rakefile!
    news.user_name = ENV['RUBYFORGE_USER']
    news.password = ENV['RUBYFORGE_PASSWORD']
  end
end

desc "Tag all the svn files with the latest release number (REL=x.y.z)"
task :tag do
  reltag = "RELEASE_#{PKG_VERSION.gsub(/\./, '_')}"
  puts "Tagging svn with [#{reltag}]"
  base_url = %{svn+ssh://#{RUBYFORGE_USER}@rubyforge.org/var/svn/autobuild}
  sh %{svn cp #{base_url}/trunk/autobuild #{base_url}/tags/#{reltag}}
end


