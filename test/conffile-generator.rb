require 'erb'

DATADIR = File.dirname(__FILE__)

class ConffileGenerator
    def self.dummy(basedir)
        apply(binding, basedir, 'dummy')
    end

    def self.apply(binding, basedir, basename)
        template = File.open(File.join(DATADIR, "#{basename}.ryml")) { |f| f.readlines }.join('')
        result = ERB.new(template).result(binding)

        yml = File.join(basedir, "#{basename}.yml")
        File.open(yml, 'w+') { |f| f.write(result) }
        
        return yml
    end
end

