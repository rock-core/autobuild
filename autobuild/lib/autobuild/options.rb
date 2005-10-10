Options = Struct.new( :update, :nice,
        :srcdir, :prefix, :builddir, :logdir, 
        :verbose, :debug, :do_build,
        :daemonize, :use_http )

class Options
    def self.default
        default_values = { :update => true, :nice => 0,
            :srcdir => nil, :prefix => nil, :builddir => nil, :logdir => nil,
            :verbose => false, :debug => false, :do_build => true,
            :daemonize => false, :use_http => false }
        
        default_values.inject(Options.new) { |opt, defval|
            k, v = *defval
            opt[k] = v
            opt
        }
    end
end

