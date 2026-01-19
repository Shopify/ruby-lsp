# typed: strict
# frozen_string_literal: true

module RubyLsp
  # This class allows listeners to access contextual information about a node in the AST, such as its parent,
  # its namespace nesting, and the surrounding CallNode (e.g. a method call).
  class NodeContext
    #: type nesting_node = Prism::ClassNode | Prism::ModuleNode | Prism::SingletonClassNode | Prism::DefNode | Prism::BlockNode | Prism::LambdaNode | Prism::ProgramNode

    #: Prism::Node?
    attr_reader :node, :parent

    #: Array[nesting_node]
    attr_reader :nesting_nodes

    #: Array[String]
    attr_reader :nesting

    #: Prism::CallNode?
    attr_reader :call_node

    #: String?
    attr_reader :surrounding_method

    #: (Prism::Node? node, Prism::Node? parent, Array[nesting_node] nesting_nodes, Prism::CallNode? call_node) -> void
    def initialize(node, parent, nesting_nodes, call_node)
      @node = node
      @parent = parent
      @nesting_nodes = nesting_nodes
      @call_node = call_node

      nesting, surrounding_method = handle_nesting_nodes
      @nesting = nesting #: Array[String]
      @surrounding_method = surrounding_method #: String?
    end

    #: -> String
    def fully_qualified_name
      @fully_qualified_name ||= @nesting.join("::") #: String?
    end

    #: -> Array[Symbol]
    def locals_for_scope
      locals = []

      nesting_nodes.each do |node|
        if node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode) || node.is_a?(Prism::SingletonClassNode) ||
            node.is_a?(Prism::DefNode)
          locals.clear
        end

        locals.concat(node.locals)
      end

      locals
    end

    private

    #: -> [Array[String], String?]
    def handle_nesting_nodes
      nesting = []
      surrounding_method = nil #: String?

      nesting_nodes.each do |node|
        case node
        when Prism::ClassNode, Prism::ModuleNode
          nesting << node.constant_path.slice
        when Prism::SingletonClassNode
          nesting << singleton_class_name(nesting)
        when Prism::DefNode
          surrounding_method = node.name.to_s
          next unless node.receiver.is_a?(Prism::SelfNode)

          nesting << singleton_class_name(nesting)
        end
      end

      [nesting, surrounding_method]
    end

    #: (Array[String] nesting) -> String
    def singleton_class_name(nesting)
      "<Class:#{nesting.flat_map { |n| n.split("::") }.last}>"
    end
  end
end
