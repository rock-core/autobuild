Options = Struct.new( :update, :nice,
        :srcdir, :prefix, :builddir, :logdir, 
        :verbose, :debug,
        :daemonize, :use_http )

class Options
    def self.default
        default_values = { :update => true, :nice => 0,
            :srcdir => nil, :prefix => nil, :builddir => nil, :logdir => nil,
            :verbose => false, :debug => false,
            :daemonize => false, :use_http => false }
        Options.new default_values
    end
end

