require 'data_graph/node'

module DataGraph

  # Graph is a wrapper that adds high-level functionality to nodes which, for
  # the most part, are intended to be throwaway objects.  Specifically Graph
  # provides a way to define/resolve path aliases, and to work with named
  # subsets for quick reuse and path validation.
  
  # Graph is a graph (perhaps not in the strictest computer-science sense) of
  # nodes which each correspond to an ActiveRecord model. The nodes are linked
  # by linkages which correspond to associations.
  #
  # A graph is defined using a options hash that states what columns may be
  # selected at each node, and what associations may be included using a subset of
  # the ActiveRecord serialization syntax (specifically :only, :except, and
  # :include).  Columns and associations that are not specified in the options
  # cannot be selected by a graph.
  # 
  # Node#find delegates to the model find, and simply At a high level a graph
  # walks down the nodes as configured, making one database query per-node to
  # get (and only get) the necessary data, and then walks back up linking the
  # children to parents as defined by the linkages.
  # 
  # Indeed if you take a look at Node and Linkage you'll see they're
  # constructed using the information tracked by models and associations, and
  # they have all the low-level methods for finding parents and linking them
  # to children, as specified by the graph config. Graph is simply a
  # high-level wrapper to use nodes more easily.
  # 
  class Graph
    include Utils

    # The graph node
    attr_reader :node

    # A hash of registered (type, Node) subsets.  The :default subset points
    # to self by default, but may be unregistered with nil or with a different
    # set of paths.
    attr_reader :subsets

    # Initializes a new Graph.  Options can provide :alisas and :subsets.  The aliases
    # are merged with the default node aliases, and each subset is registered with self.
    def initialize(node, options={})
      @node = node
      @subsets = {:default => self}

      if aliases = options[:aliases]
        @aliases = node.aliases.merge(aliases)
      end

      if subsets = options[:subsets]
        subsets.each_pair do |type, paths|
          register(type, paths)
        end
      end
    end

    # Returns the node paths
    def paths
      @paths ||= node.paths
    end

    # Returns the node get_paths
    def get_paths
      @get_paths ||= node.get_paths
    end

    # Returns the node set_paths
    def set_paths
      @set_paths ||= node.set_paths
    end

    # Returns the node nest_paths
    def nest_paths
      @nest_paths ||= node.nest_paths
    end

    # Returns the node aliases.
    def aliases
      @aliases ||= node.aliases
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
    # subset.  Provide nil paths to unregister and return an existing subset.
    def register(type, paths)
      if paths.nil?
        subsets.delete(type)
      else
        subsets[type] = only(paths)
      end
    end

    # Returns the specified subset, or the default subset if no subset is
    # registered to type.  Raises an error if neither subset is registered.
    def subset(type)
      (subsets[type] || subsets[:default]) or raise "no such subset: #{type.inspect}"
    end

    # Validates that the paths are all accessible by the named subset.  The
    # input paths are not resolved against aliases.  Raises an
    # InaccessiblePathError if the paths are not accessible.
    def validate(type, paths)
      inaccessible_paths = paths - subset(type).get_paths
      unless inaccessible_paths.empty?
        raise InaccessiblePathError.new(inaccessible_paths)
      end

      paths
    end

    # Validates that all paths in the attrs hash are assignable by the named
    # subset.  The input paths are not resolved against aliases.  Raises an
    # InaccessiblePathError if the paths are not accessible.
    def validate_attrs(type, attrs)
      paths = patherize_attrs(attrs, nest_paths)

      inaccessible_paths = paths - subset(type).set_paths
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