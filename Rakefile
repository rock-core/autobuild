require 'hoe'
require './lib/autobuild'

Hoe.new('autobuild', Autobuild::VERSION) do |p|
    p.author = "Sylvain Joyeux"
    p.email = "sylvain.joyeux@m4x.org"

    p.summary = 'Rake-based utility to build and install multiple packages with dependencies'
    p.url	  = p.paragraphs_of('README.txt', 0).first.split(/\n/)[1..-1]
    p.description = p.paragraphs_of('README.txt', 3..5).join("\n\n")
    p.changes     = p.paragraphs_of("Changes.txt", 1).join("\n\n")
    p.extra_deps = [['rake', '>= 0.7.0']]
    p.extra_deps << ['rmail']
    p.extra_deps << ['daemons']
end

