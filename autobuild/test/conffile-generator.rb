require 'tmpdir'
require 'erb'

DATADIR = File.dirname(__FILE__)

class ConffileGenerator
    class << self
        def tempdir
            @tmpdir = Dir::tmpdir + "/autobuild-#{Process.uid}"
            FileUtils.mkdir_p(@tmpdir, :mode => 0700)
        end

        def dummy(basedir = tempdir)
            apply(binding, basedir, 'dummy')
        end

        def clean
            FileUtils.rm_rf tempdir
        end

        private

        def apply(binding, basedir, basename)
            template = File.open(File.join(DATADIR, "#{basename}.ryml")) { |f| f.readlines }.join('')
            result = ERB.new(template).result(binding)

            yml = File.join(basedir, "#{basename}.yml")
            File.open(yml, 'w+') { |f| f.write(result) }
            
            return yml
        end
    end
end

