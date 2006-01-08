class << Class
    alias :__attr_reader__   :attr_reader

    @attr_defval = Hash.new
    def self.attr_reader(*args)
        args.each do |a|
            if a.is_a?(Hash)
                a.each do |name, defval|
                    instance_eval { @attr_defval[name.to_sym] = defval }
                end
                a = a.keys
            else
                a = Array[a]
            end
            a.each do |name|
                instance_eval <<-EOV
                    def #{name}; @#{name} || @attr_defval[:#{name}] end
                EOV
            end
        end
    end
end


