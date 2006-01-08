require 'autobuild'

include Autobuild

openrobots_config = Proc.new { |pkg|
    pkg.import = cvs(openrobots, pkg.name)
    pkg.depends_on :mkdep
}

Autotools.aclocal  = "aclocal-1.9"
Autotools.automake = "automake-1.9"
    
autotools(:mkdep, &openrobots_config)
autotools(:gdhe, &openrobots_config)
autotools(:pocolibs, &openrobots_config)
autotools :genom do |pkg|
    openrobots_config(pkg)
    pkg.autoheader = true
end
