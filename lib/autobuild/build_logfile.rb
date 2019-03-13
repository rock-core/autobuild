require 'time'

module Autobuild
    # Parse and manipulate the information stored in a build log file (usually
    # in prefix/log/stats.log)
    class BuildLogfile
        Entry = Struct.new :package, :phase, :start_time, :duration

        attr_reader :by_package
        attr_reader :by_phase

        def initialize(entries = Array.new)
            @entries = entries.dup
            @by_package = Hash.new
            entries.each do |e|
                package = (by_package[e.package] ||= Hash.new(0))
                package[e.phase] += e.duration
            end

            @by_phase = Hash.new
            entries.each do |e|
                package = (by_phase[e.phase] ||= Hash.new(0))
                package[e.package] += e.duration
            end
        end

        def diff(other)
            result = []
            by_package.each do |pkg_name, phases|
                other_phases = other.by_package[pkg_name]
                next unless other_phases
                phases.each do |phase, duration|
                    next unless other_phases.has_key?(phase)
                    other_duration = other_phases[phase]
                    result << Entry.new(pkg_name, phase, nil, other_duration - duration)
                end
            end
            BuildLogfile.new(result)
        end

        def self.parse(file)
            entries = File.readlines(file).map do |line|
                line = line.strip
                next if line.empty?

                cols = line.split(/\s+/)
                date, time = cols.shift, cols.shift
                start_time = Time.parse("#{date} #{time}")
                duration = Float(cols.pop)
                phase = cols.pop
                package = cols.join(" ")
                Entry.new(package, phase, start_time, duration)
            end
            new(entries)
        end
    end
end
