require 'autobuild/config'
require 'find'
require 'rake/tasklib'
require 'fileutils'

STAMPFILE = "autobuild-stamp"

module Autobuild
    def self.tree_timestamp(path, *exclude)
        # Exclude autobuild timestamps
	exclude.each { |rx| raise unless Regexp === rx }
        exclude << (/#{Regexp.quote(STAMPFILE)}$/)

        puts "getting tree timestamp for #{path}" if Autobuild.debug
        latest = Time.at(0)
        latest_file = ""

        Find.find(path) { |p|
            Find.prune if File.basename(p) =~ /^\./
            exclude.each { |pattern| 
                if p =~ pattern
                    puts "  excluding #{p}" if Autobuild.debug
                    Find.prune
                end
            }
            next if !File.file?(p)

            p_time = File.mtime(p)
            if latest < p_time
                latest = p_time
                latest_file = p
            end
        }

        puts "  newest file: #{latest_file} at #{latest}" if Autobuild.debug
        return latest
    end

    class SourceTreeTask < Rake::Task
        attr_accessor :exclude
	def initialize(*args, &block)
	    @exclude = []
	    super
	end
	    
        def timestamp
            Autobuild.tree_timestamp(name, %r#(?:^|/)(?:CVS|_darcs|\.svn)$#, *@exclude)
        end
    end
    def self.source_tree(path, &block)
        task = SourceTreeTask.define_task(path)
        block.call(task) unless !block
        task
    end
            
    def self.get_stamp(stampfile)
        return Time.at(0) if !File.exists?(stampfile)
        return File.mtime(stampfile)
    end

    def self.hires_modification_time?
        if @hires_modification_time.nil?
            Tempfile.open('test') do |io|
                io.flush
                p_time = File.mtime(io.path)
                @hires_modification_time = (p_time.tv_usec != 0)
            end
        end
        @hires_modification_time
    end

    def self.touch_stamp(stampfile)
        puts "Touching #{stampfile}" if Autobuild.debug
        dir = File.dirname(stampfile)
        if File.exists?(dir) && !File.directory?(dir)
            raise "#{dir} exists and is not a directory"
        elsif !File.exists?(dir)
            FileUtils.mkdir_p dir
        end
        FileUtils.touch(stampfile)

        if !hires_modification_time?
            # File modification times on most Unix filesystems have a granularity of
            # one second, so we (unfortunately) have to sleep 1s to make sure that
            # time comparisons will work as expected.
            sleep(1)
        end
    end
end

