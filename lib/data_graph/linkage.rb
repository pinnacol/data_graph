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
    attr_reader :reflection

    def initialize(assoc, options={})
      @macro = assoc.macro
      @name = assoc.name
      @through = nil
      @reflection = assoc

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
      ["#{table_name}.#{connection.quote_column_name(child_columns.at(0))} IN (?)", id_map.keys.flatten]
    end

    def link(parents)
      id_map = Hash.new {|hash, key| hash[key] = [] }

      parents = arrayify(parents)
      parents.each do |parent|
        id_map[parent_id(parent)] << parent
      end

      children = child_node.find(:all,
        :select => child_columns,
        :conditions => conditions(id_map))
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
        child = child.send(through)
      end

      association = reflection.association_class.new(parent, reflection)
      association.loaded!

      case macro
      when :belongs_to, :has_one
        association.target = child
      when :has_many
        association.target.push(child) if child
      else
        # should never get here...
      end
    end
  end
end
