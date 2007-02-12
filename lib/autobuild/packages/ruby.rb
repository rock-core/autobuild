require 'autobuild/timestamps'
require 'autobuild/package'
require 'enumerator'

module Autobuild
    def self.ruby(spec, &proc)
        RubyPackage.new(spec, &proc)
    end
    
    class RubyPackage < Package
	# The list of all extension directories
	attr_reader :extdir

        def installstamp
            "#{srcdir}/#{STAMPFILE}"
        end
        def initialize(target)
            super
            source_tree srcdir, [/Makefile$/, /\.(?:so|o)$/]
            file installstamp => srcdir do 
                touch_stamp installstamp
            end
        end

	def prepare
	    @extdir = Find.enum_for(:find, srcdir).
		grep(/extconf.rb$/).
		map { |f| File.dirname(f) }

	    extdir.each do |dir|
		file "#{dir}/Makefile" => "#{dir}/extconf.rb" do
		    Dir.chdir(dir) do
			Subprocess.run(name, 'ext', Autobuild.tool('ruby'), 'extconf.rb')
		    end
		end
	    end
	end

	def extstamp(dir); "#{dir}/ext-#{STAMPFILE}" end
	def build
	    extdir.each do |dir|
		source_tree dir, [/Makefile$/, /\.(?:so|o)$/]
		file extstamp(dir) => dir do
		    Dir.chdir(dir) do
			Subprocess.run(name, 'ext', Autobuild.tool('make'))
			touch_stamp extstamp(dir)
		    end
		end
	    end
	end
    end
end

