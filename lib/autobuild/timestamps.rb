require 'autobuild/config'
require 'find'
require 'rake/tasklib'
require 'fileutils'

STAMPFILE = "autobuild-stamp"

module Autobuild
    def tree_timestamp(path, *exclude)
        # Exclude autobuild timestamps
        exclude << "*-#{STAMPFILE}"

        puts "getting tree timestamp for #{path}" if Autobuild.debug
        latest = Time.at(0)
        latest_file = ""

        exclude.collect! { |e| File.expand_path(e, path) }
        Find.find(path) { |p|
            Find.prune if File.basename(p) =~ /^\./
            exclude.each { |pattern| 
                if File.fnmatch?(pattern, p) 
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

        puts "  #{latest}" if Autobuild.debug
        return latest
    end

    class SourceTreeTask < Rake::Task
        attr_accessor :exclude
        def timestamp
            tree_timestamp(name, "*CVS", *@exclude)
        end
    end
    def source_tree(path, exclude, &block)
        task = SourceTreeTask.define_task(path, &block)
        task.exclude = exclude
    end
            
    def get_stamp(stampfile)
        return Time.at(0) if !File.exists?(stampfile)
        return File.mtime(stampfile)
    end

    def touch_stamp(stampfile)
        puts "Touching #{stampfile}" if Autobuild.debug
        FileUtils.touch(stampfile)
        sleep(1)
    end
end

