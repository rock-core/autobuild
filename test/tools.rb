require 'tmpdir'
require 'erb'
require 'fileutils'

module TestTools
    DATADIR = File.join(File.dirname(__FILE__), 'data')

    def self.tempdir
        @tmpdir = File.join(Dir::tmpdir, "/autobuild-test-#{Process.uid}")
        FileUtils.mkdir_p(@tmpdir, :mode => 0700)
    end

    def self.clean
        FileUtils.rm_rf tempdir
    end

    def self.build_config(bind, template)
        eval "basedir = '#{self.tempdir}'", bind
        ryml = File.open(File.join(DATADIR, "#{template}.ryml")) { |f| f.readlines }.join('')
        result = ERB.new(ryml).result(bind)

        yml = File.join(tempdir, "#{template}.yml")
        File.open(yml, 'w+') { |f| f.write(result) }
        
        return yml
    end

    def self.untar(file)
        file = File.expand_path(file, DATADIR)
        dir = self.tempdir
        Dir.chdir(dir) do 
            system("tar xf #{file}")
        end

        dir
    end
end


