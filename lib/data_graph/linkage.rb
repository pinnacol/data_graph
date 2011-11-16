require 'data_graph/utils'

module DataGraph
  class Linkage
    include Utils

    attr_reader :macro
    attr_reader :name
    attr_reader :through
    attr_reader :table_name
    attr_reader :connection
    attr_reader :parent_columns
    attr_reader :child_columns
    attr_reader :child_node
    attr_reader :order
    attr_reader :limit
    attr_reader :group
    attr_reader :readonly
    attr_reader :assoc_conditions

    def initialize(assoc, options={})
      @macro = assoc.macro
      @name = assoc.name
      @through = nil

      case macro
      when :belongs_to
        @parent_columns = foreign_key(assoc)
        @child_columns  = reference_key(assoc)
      when :has_many, :has_one
        if through_assoc = assoc.through_reflection
          @through = assoc.source_reflection.name

          assoc = through_assoc
          options = {:only => [], :include => {@through => options}}
        end

        @parent_columns = reference_key(assoc)
        @child_columns  = foreign_key(assoc)
      else
        raise "currently unsupported association macro: #{macro}"
      end

      @assoc_conditions = assoc.sanitized_conditions ? " AND #{assoc.sanitized_conditions}" : nil
      @order = options[:order]
      @limit = options[:limit]
      @group = options[:group]
      @readonly = options[:readonly]

      klass = assoc.klass
      @child_node = Node.new(assoc.klass, options)
      @table_name = klass.table_name
      @connection = klass.connection
    end

    def node
      through ? child_node[through] : child_node
    end

    def parent_id(record)
      record.read_attribute_before_type_cast parent_columns.at(0)
    end

    def child_id(record)
      record.read_attribute_before_type_cast child_columns.at(0)
    end

    def conditions(id_map)
      ["#{table_name}.#{connection.quote_column_name(child_columns.at(0))} IN (?)#{assoc_conditions}", id_map.keys.flatten]
    end

    #--
    # Query through using the association options.
    #
    # BT
    # :select     => @reflection.options[:select],   # overidden
    # :conditions => conditions,                     # add
    # :include    => @reflection.options[:include],  # overidden
    # :readonly   => @reflection.options[:readonly]  # add
    #
    # BT-Poly
    # :select     => @reflection.options[:select],
    # :conditions => conditions,
    # :include    => @reflection.options[:include]
    # 
    # HMT
    # :select     => construct_select,               # overidden
    # :conditions => construct_conditions,           # add
    # :from       => construct_from,                 # irrelevant?
    # :joins      => construct_joins,                # irrelevant?
    # :order      => @reflection.options[:order],    # add
    # :limit      => @reflection.options[:limit],    # add
    # :group      => @reflection.options[:group],    # add
    # :readonly   => @reflection.options[:readonly], # add
    # :include    => @reflection.options[:include] || @reflection.source_reflection.options[:include] # overridden
    #
    # HO
    # :conditions => @finder_sql,                    # add
    # :select     => @reflection.options[:select],   # overidden
    # :order      => @reflection.options[:order],    # add
    # :include    => @reflection.options[:include],  # overidden
    # :readonly   => @reflection.options[:readonly]  # add
    def link(parents)
      parents = arrayify(parents)
      return [] if parents.empty?

      id_map = Hash.new {|hash, key| hash[key] = [] }
      parents.each do |parent|
        id_map[parent_id(parent)] << parent
      end

      children = child_node.find(:all,
        :select => child_columns,
        :conditions => conditions(id_map),
        :order => order,
        :limit => limit,
        :group => group,
        :readonly => readonly
      )
      visited = []

      arrayify(children).each do |child|
        id_map[child_id(child)].each do |parent|
          visited << parent
          set_child(parent, child)
        end
      end

      if macro == :has_many && through
        visited.each do |parent|
          parent.send(name).uniq!
        end
      end

      (parents - visited).each do |parent|
        set_child(parent, nil)
      end

      children
    end

    def inherit(method_name, paths)
      dup.inherit!(method_name, paths)
    end

    def inherit!(method_name, paths)
      paths = paths.collect {|path| "#{through}.#{path}"} if through
      @child_node = @child_node.send(method_name, paths)
      self
    end

    private

    def arrayify(obj) # :nodoc:
      obj.kind_of?(Array) ? obj : [obj]
    end

    def set_child(parent, child) # :nodoc:
      if child && through
        child = child.send(through).target
      end

      case macro
      when :belongs_to, :has_one
        parent.send("set_#{name}_target", child)
      when :has_many
        association_proxy = parent.send(name)
        association_proxy.loaded
        association_proxy.target.push(child) if child
      else
        # should never get here...
      end
    end
  end
end
