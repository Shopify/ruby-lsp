# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class ReferencesVisitor < YARP::Visitor
    extend T::Sig

    sig { returns(T::Array[Reference]) }
    attr_reader :references

    sig { params(index: Index, path: String, fully_qualified_name: String).void }
    def initialize(index, path, fully_qualified_name)
      @index = index
      @path = path
      @fully_qualified_name = fully_qualified_name
      @nesting = T.let([], T::Array[String])
      @references = T.let([], T::Array[Reference])
      super()
    end

    sig { override.params(node: YARP::ConstantReadNode).void }
    def visit_constant_read_node(node)
      name = node.name.to_s
      check_reference_for(name, node)
    end

    sig { override.params(node: YARP::ConstantPathNode).void }
    def visit_constant_path_node(node)
      name = node.slice
      check_reference_for(name, node)
    end

    sig { override.params(node: YARP::ClassNode).void }
    def visit_class_node(node)
      name = node.constant_path.slice
      @nesting << name
      visit(node.body)
      @nesting.pop
    end

    sig { override.params(node: YARP::ModuleNode).void }
    def visit_module_node(node)
      name = node.constant_path.slice
      @nesting << name
      visit(node.body)
      @nesting.pop
    end

    private

    sig { params(name: String, node: T.any(YARP::ConstantReadNode, YARP::ConstantPathNode)).void }
    def check_reference_for(name, node)
      entries = @index.resolve(name, @nesting)
      return unless entries

      first_entry = T.must(entries.first)
      return if first_entry.visibility == :private && first_entry.name != "#{@nesting.join("::")}::#{name}"

      entry_name = T.must(entries.first).name
      @references << Reference.new(node.location, @path) if entry_name == @fully_qualified_name
    end
  end
end
