require 'autobuild'

# Remove the need for the Autobuild. prefix in
# front of everything
include Autobuild

# Define a common configuration routine
openrobots_config = lambda { |pkg|
    pkg.import = cvs(openrobots, pkg.name)
    pkg.depends_on :mkdep
}

Autotools.aclocal  = "aclocal-1.9"
Autotools.automake = "automake-1.9"
    
autotools(:mkdep, &openrobots_config)
autotools(:gdhe, &openrobots_config)
autotools(:pocolibs, &openrobots_config)
autotools :genom do |pkg|
    openrobots_config[pkg]
    pkg.autoheader = true     # Force usage of autoheader
    pkg.automake = 'automake' # use the default automake instead
			      # of Autotools.automake
end

