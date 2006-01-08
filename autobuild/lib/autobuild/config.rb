class Autobuild::Config
    class << self
        attr_reader :srcdir, :prefix, :programs
    end
    @programs = Hash.new

    ## Get a given program, using its name as default value
    def tool(name)
        Config.programs[name.to_sym] || name.to_s
    end
end

