require 'data_graph/node'

module DataGraph

  # Graph provides a simplified interface to a Node.  In addition Graph adds
  # support for aliases and named subsets, but mainly Graph is a convenience
  # wrapper.
  #
  # == Configuration
  #
  # These configurations are available to a Graph:
  #
  # aliases:: A hash of (name, [paths]) pairs identifying aliases that are
  #           resovled to other paths by resolve.  The configured aliases are
  #           merged with the default aliases for node.
  # subsets:: A hash of (name, [paths]) pairs identifying a named subset of
  #           paths.  The subset paths are resolved to actual Node in the
  #           subsets attribute.
  #
  class Graph
    include Utils

    # The wrapped node
    attr_reader :node

    # A hash of (name, [paths]) pairs identifying aliases expanded by resolve.
    attr_reader :aliases

    # A hash of (name, Node) pairs identifying named subsets.  The :default
    # subset points to self by default, but may be unregistered with nil or
    # with a different set of paths.
    attr_reader :subsets

    def initialize(node, options={})
      @node = node
      @subsets = {:default => self}

      if aliases = options[:aliases]
        @aliases = node.aliases.merge(aliases)
      else
        @aliases = node.aliases
      end

      if subsets = options[:subsets]
        subsets.each_pair do |name, paths|
          register(name, paths)
        end
      end
    end

    # Returns the node paths.
    def paths
      @paths ||= node.paths
    end

    # Returns the node get_paths.
    def get_paths
      @get_paths ||= node.get_paths
    end

    # Returns the node set_paths.
    def set_paths
      @set_paths ||= node.set_paths
    end

    # Returns the node nest_paths.
    def nest_paths
      @nest_paths ||= node.nest_paths
    end

    # Delegates to Node#find.
    def find(*args)
      node.find(*args)
    end

    # Delegates to Node#paginate.
    def paginate(*args)
      node.paginate(*args)
    end

    # Resolves paths and generates a subset graph using Node#only.
    def only(paths)
      Graph.new node.only(resolve(paths))
    end

    # Resolves paths and generates a subset graph using Node#except.
    def except(paths)
      Graph.new node.except(resolve(paths))
    end

    # Resolves paths using aliases. Returns an array of unique paths.
    def resolve(paths)
      paths = paths.collect {|path| aliases[path] || path }
      paths.flatten!
      paths.uniq!
      paths
    end

    # Registers a new subset defined by only(paths) and returns the new
    # subset.  Provide nil paths to unregister an existing subset.
    def register(name, paths)
      if paths.nil?
        subsets.delete(name)
      else
        subsets[name] = only(paths)
      end
    end

    # Returns the specified subset.  Raises an error if the subset is not
    # registered.
    def subset(name)
      subsets[name] or raise "no such subset: #{name.inspect}"
    end

    # Validates that the paths are all accessible by the named subset.  The
    # input paths are not resolved against aliases.  Raises an
    # InaccessiblePathError if the paths are not accessible.
    def validate(name, paths)
      inaccessible_paths = paths - subset(name).get_paths
      unless inaccessible_paths.empty?
        raise InaccessiblePathError.new(inaccessible_paths)
      end

      paths
    end

    # Validates that all paths in the attrs hash are assignable by the named
    # subset.  The input paths are not resolved against aliases.  Raises an
    # InaccessiblePathError if the paths are not accessible.
    def validate_attrs(name, attrs)
      paths = patherize_attrs(attrs, nest_paths)

      inaccessible_paths = paths - subset(name).set_paths
      unless inaccessible_paths.empty?
        raise InaccessiblePathError.new(inaccessible_paths)
      end

      attrs
    end
  end

  # Raised to indicate inaccessible paths, as determined by Graph#validate.
  class InaccessiblePathError < RuntimeError
    attr_reader :paths

    def initialize(paths)
      @paths = paths
      super "inaccessible: #{paths.inspect}"
    end
  end
end