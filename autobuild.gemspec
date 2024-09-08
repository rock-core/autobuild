lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'autobuild/version'

Gem::Specification.new do |s|
    s.name = "autobuild"
    s.version = Autobuild::VERSION
    s.required_ruby_version = '>= 2.5.0'
    s.authors = ["Sylvain Joyeux"]
    s.email = "sylvain.joyeux@m4x.org"
    s.summary = "Library to handle build systems and import mechanisms"
    s.description = "Collection of classes to handle build systems "\
        "(CMake, autotools, ...) and import mechanisms "\
        "(tarballs, CVS, SVN, git, ...). It also offers a Rake integration "\
        "to import and build such software packages. It is the backbone "\
        "of the autoproj (http://rock-robotics.org/autoproj) integrated "\
        "software project management tool."
    s.homepage = "http://rock-robotics.org"
    s.licenses = ["BSD"]

    s.require_paths = ["lib"]
    s.extensions = []
    s.files = `git ls-files -z`.split("\x0")
        .reject { |f| f.match(%r{^(test|spec|features)/}) }

    s.add_runtime_dependency "concurrent-ruby", "~> 1.1"
    s.add_runtime_dependency "net-smtp"
    s.add_runtime_dependency "pastel", "~> 0.7.0"
    s.add_runtime_dependency "rake", "~> 13.0"
    s.add_runtime_dependency 'tty-cursor', '~> 0.7.0'
    s.add_runtime_dependency 'tty-prompt', '~> 0.21.0'
    s.add_runtime_dependency 'tty-screen', '~> 0.8.0'
    s.add_runtime_dependency "utilrb", "~> 3.0", ">= 3.0"
    s.add_development_dependency "fakefs"
    s.add_development_dependency "flexmock"
    s.add_development_dependency "minitest", "~> 5.0", ">= 5.0"
    s.add_development_dependency "simplecov"
    s.add_development_dependency "timecop"
    s.add_development_dependency "webrick"
end
