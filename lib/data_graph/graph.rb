require 'data_graph/node'

module DataGraph

  # = Understanding Graph/DataGraph
  #
  # So DataGraph suffers from several dubiously named classes.  Regardless,
  # here is the conceptual breakdown:
  #
  #   Graph      a wrapper for a Node, providing a useful interface
  #   Node       corresponds to a model
  #   Linkage    corresponds to an association
  #
  # The 'graph' in DataGraph is composed of nodes where edges are linkages, or
  # equivalently models joined by associations.  Note, however the 'graph' is
  # really just a tree because nodes are not re-used... if associations link
  # back to a model, then there will be two nodes for that model.
  #
  #   [job] -> [employee] -> [job]
  #
  # Nodes provide methods to traverse linkages to other nodes in order to
  # query records, determine paths, or create serialization parameters.  It's
  # essentially a lot of visitation and aggregation, based on the graph
  # options.
  # 
  # Note that the options apply differently in queries, paths, and
  # serialization. For example, :methods are included in paths and
  # serialization (because you can't query a method from a database, only a
  # column). By contrast, :always is only included in queries.
  #
  # == Queries
  #
  # During a query, the node for a graph will scope normal ActiveRecord#find
  # options using the node conditions.  Specifically the find options will be
  # adjusted such that:
  #
  #   * columns disallowed by :only/:except are removed
  #   * :always columns are added
  #   * the id/foreign keys required for :include are added
  #
  # Then, using the results as parents records, the node traverses linkages to
  # adjacent nodes and finds child records.  Once all the nodes have been
  # traversed, the children are linked back with their parents.
  # 
  # In other words, graphs use a 'one query per-association' query strategy to
  # eagerly load all data specified by the graph.  All unspecified data is
  # unavailable.  The nodes do not actually do the finds themselves, instead
  # they proxy to ActiveRecord#find to do the work.
  # 
  # == Paths
  #
  # As with queries, a node determines what paths are available to it by
  # traversing the nodes and linking all the methods that can be called at
  # each node.  The methods available at each level are:
  #
  #  * columns allowed by :only/:except
  #  * :methods
  #  * the methods to access each :include association
  # 
  # Paths can be used to create subset graphs where the subset graph is
  # further constrained to the subset paths.
  #
  # == Serialization Options
  #
  # The same traversal technique is used to put together serialization
  # options.  Serialization options represent the same information as in
  # paths, but in a hash format that works with ActiveRecord::Serialization.
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