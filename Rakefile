require 'utilrb/rake_common'

Utilrb::Rake.hoe do
    Hoe.spec 'autobuild' do
        developer "Sylvain Joyeux", "sylvain.joyeux@m4x.org"

        self.summary = 'Rake-based utility to build and install multiple packages with dependencies'
        self.description = self.paragraphs_of('README.txt', 2..5).join("\n\n")
        self.url         = self.paragraphs_of('README.txt', 1).first.split(/\n/)[1..-1].map { |s| s.gsub('* ', '') }
        self.changes     = self.paragraphs_of('Changes.txt', 0..2).join("\n\n")

        self.extra_deps <<
            ['rake', '>= 0.7.0'] <<
            ['utilrb', '>= 1.3.3']
    end
    Rake.clear_tasks(/publish_docs/, /default/)
end

task "default"

