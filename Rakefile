require 'utilrb/rake_common'

Utilrb::Rake.hoe do
    Hoe.spec 'autobuild' do
        developer "Sylvain Joyeux", "sylvain.joyeux@m4x.org"

        self.urls         = ["http://rock-robotics.org/stable/documentation/autoproj"]
        self.summary = 'Library to handle build systems and import mechanisms'
        self.description = "Collection of classes to handle build systems (CMake, autotools, ...) and import mechanisms (tarballs, CVS, SVN, git, ...). It also offers a Rake integration to import and build such software packages. It is the backbone of the autoproj (http://rock-robotics.org/autoproj) integrated software project management tool."
        self.email = %q{rock-dev@dfki.de}

        license 'BSD'

        self.spec_extras[:required_ruby_version] = ">= 1.9.2"

        self.extra_deps <<
            ['rake', '>= 0.9.0'] <<
            ['utilrb', '~> 2.0.0'] <<
            ['highline', '>= 0']

        self.test_globs = ['test/suite.rb']
    end
    Rake.clear_tasks(/publish_docs/, /default/)
end

task "default"

