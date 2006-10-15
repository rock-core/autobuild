require 'rubygems'
require 'hoe'

$:.unshift('lib')

Hoe.new('autobuild', "0.6.2") do |p|
    p.author = "Sylvain Joyeux"
    p.email = "sylvain.joyeux@m4x.org"
    p.summary = 'Rake-based utility to build and install multiple packages with dependencies'
    p.url = "http://autobuild.rubyforge.org"
    p.description = <<-EOF
    Autobuild imports, configures, builds and installs various kinds of software packages.
    It can be used in software development to make sure that nothing is broken in the 
    build process of a set of packages, or can be used as an automated installation tool.
    EOF
    p.changes = p.paragraphs_of("CHANGES", 1).join("\n\n")
    p.extra_deps << ['rake', '>= 0.7.0']
    p.extra_deps << ['rmail']
    p.extra_deps << ['daemons']
end

