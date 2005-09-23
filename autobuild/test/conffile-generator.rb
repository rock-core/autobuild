require 'tmpdir'
require 'erb'
require 'fileutils'

DATADIR = File.join(File.dirname(__FILE__), 'data')

class ConffileGenerator
    def self.tempdir
        @tmpdir = File.join(Dir::tmpdir, "/autobuild-test-#{Process.uid}")
        FileUtils.mkdir_p(@tmpdir, :mode => 0700)
    end

    def self.build(bind, template)
        eval "basedir = '#{ConffileGenerator.tempdir}'", bind
        ryml = File.open(File.join(DATADIR, "#{template}.ryml")) { |f| f.readlines }.join('')
        result = ERB.new(ryml).result(bind)

        yml = File.join(tempdir, "#{template}.yml")
        File.open(yml, 'w+') { |f| f.write(result) }
        
        return yml
    end

    def self.clean
        FileUtils.rm_rf tempdir
    end
end

