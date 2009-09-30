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
            next if File.directory?(p)

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

    def self.touch_stamp(stampfile)
        puts "Touching #{stampfile}" if Autobuild.debug
        FileUtils.touch(stampfile)

        # File modification times on most Unix filesystems have a granularity of
        # one second, so we (unfortunately) have to sleep 1s to make sure that
        # time comparisons will work as expected.
        sleep(1)
    end
end

