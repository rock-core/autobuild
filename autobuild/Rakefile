require 'rubygems'
require 'rake/gempackagetask'

spec = Gem::Specification.new do |s|
    s.name = 'autobuild'
    s.version = '0.4'
    s.author = 'Sylvain Joyeux'
    s.email = 'sylvain.joyeux@m4x.org'
    s.summary = 'Rake-based utility to build and install multiple packages with dependencies'
    s.description = <<EOF
autobuild imports, configures, builds and installs software packages (mainly 
C/C++ autotools packages for now) with dependencies. It can be used in 
community-based software development to make sure that nothing is broken
in the build process of a set of packages.
EOF

    s.has_rdoc = true
    s.extra_rdoc_files = 'README'
    s.rdoc_options << '--title' << 'Autobuild' << '--main' << 'README'

    s.platform = Gem::Platform::RUBY
    s.require_paths << "lib"
    s.add_dependency('rake', '>= 0.6.0')
    s.add_dependency('rmail')
    s.add_dependency('daemons')
    s.files = FileList['lib/**/*.rb', 'bin/*', 'README']
    s.test_files = FileList['test/*' ]
    s.executables = 'autobuild'
end

Rake::GemPackageTask.new(spec) do |pkg| end

