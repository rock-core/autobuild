class Autobuild::Config
    @config = Hash.new
    def self.config_option(defval, name)
        @config_defval[name.id2name] = defval
        class_eval <<-EOV
                def self.#{name}; @config[:#{name}] ||= @config_defval[:#{name}] end
                def self.#{name}=(value); @config[:#{name}] end
        EOV
    end

    config_option '', :srcdir
    config_option '', :prefix
    config_option Hash.new, :programs
    
    ## Get a given program, using its name as default value
    def tool(name)
        name = name.to_sym
        Config.programs[name] || name.id2name 
    end
end
