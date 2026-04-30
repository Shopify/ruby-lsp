# typed: strict
# frozen_string_literal: true

module RubyLsp
  # This class allows listeners to access contextual information about a node in the AST, such as its parent,
  # its namespace nesting, and the surrounding CallNode (e.g. a method call).
  class NodeContext
    # Represents the surrounding method definition context, tracking both the method name and its receiver
    class MethodDef
      #: String
      attr_reader :name

      #: String?
      attr_reader :receiver

      #: (String name, String? receiver) -> void
      def initialize(name, receiver)
        @name = name
        @receiver = receiver
      end
    end

    #: Prism::Node?
    attr_reader :node, :parent

    #: Array[String]
    attr_reader :nesting

    #: Prism::CallNode?
    attr_reader :call_node

    #: MethodDef?
    attr_reader :surrounding_method

    #: (Prism::Node? node, Prism::Node? parent, Array[(Prism::ClassNode | Prism::ModuleNode | Prism::SingletonClassNode | Prism::DefNode | Prism::BlockNode | Prism::LambdaNode | Prism::ProgramNode)] nesting_nodes, Prism::CallNode? call_node) -> void
    def initialize(node, parent, nesting_nodes, call_node)
      @node = node
      @parent = parent
      @nesting_nodes = nesting_nodes
      @call_node = call_node

      nesting, surrounding_method = handle_nesting_nodes(nesting_nodes)
      @nesting = nesting #: Array[String]
      @surrounding_method = surrounding_method #: MethodDef?
    end

    #: -> String
    def fully_qualified_name
      @fully_qualified_name ||= @nesting.join("::") #: String?
    end

    #: -> Array[Symbol]
    def locals_for_scope
      locals = []

      @nesting_nodes.each do |node|
        if node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode) || node.is_a?(Prism::SingletonClassNode) ||
            node.is_a?(Prism::DefNode)
          locals.clear
        end

        locals.concat(node.locals)
      end

      locals
    end

    private

    #: (Array[(Prism::ClassNode | Prism::ModuleNode | Prism::SingletonClassNode | Prism::DefNode | Prism::BlockNode | Prism::LambdaNode | Prism::ProgramNode)] nodes) -> [Array[String], MethodDef?]
    def handle_nesting_nodes(nodes)
      nesting = []
      surrounding_method = nil #: MethodDef?

      @nesting_nodes.each do |node|
        case node
        when Prism::ClassNode, Prism::ModuleNode
          nesting << node.constant_path.slice
        when Prism::SingletonClassNode
          nesting << "<#{nesting.flat_map { |n| n.split("::") }.last}>"
        when Prism::DefNode
          receiver = node.receiver

          surrounding_method = case receiver
          when nil
            MethodDef.new(node.name.to_s, "none")
          when Prism::SelfNode
            MethodDef.new(node.name.to_s, "self")
          when Prism::ConstantReadNode, Prism::ConstantPathNode
            MethodDef.new(node.name.to_s, receiver.slice)
          else
            MethodDef.new(node.name.to_s, nil)
          end
        end
      end

      [nesting, surrounding_method]
    end
  end
end
