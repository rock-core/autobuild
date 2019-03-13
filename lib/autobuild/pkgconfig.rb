# Access to information from pkg-config(1)
class PkgConfig
    class NotFound < RuntimeError
        attr_reader :name

        def initialize(name)
            @name = name
        end

        def to_s
            "#{name} is not available to pkg-config"
        end
    end

    # The module name
    attr_reader :name
    # The module version
    attr_reader :version

    # Create a PkgConfig object for the package +name+
    # Raises PkgConfig::NotFound if the module does not exist
    def initialize(name)
        unless system("pkg-config --exists #{name}")
            raise NotFound.new(name), "pkg-config package '#{name}' not found"
        end

        @name    = name
        @version = `pkg-config --modversion #{name}`.chomp.strip
        @actions = Hash.new
        @variables = Hash.new
    end

    ACTIONS = %w[cflags cflags-only-I cflags-only-other
                 libs libs-only-L libs-only-l libs-only-other static].freeze
    ACTIONS.each do |action|
        define_method(action.tr('-', '_')) do
            @actions[action] ||= `pkg-config --#{action} #{name}`.chomp.strip
        end
    end

    def method_missing(varname, *args, &proc) # rubocop:disable Style/MissingRespondToMissing
        if args.empty?
            unless (value = @variables[varname])
                value = `pkg-config --variable=#{varname} #{name}`.chomp.strip
                @variables[varname] = value
            end
            return value
        end
        super
    end
end
