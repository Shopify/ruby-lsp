# typed: strict
# frozen_string_literal: true

module RubyLsp
  # This class allows listeners to access contextual information about a node in the AST, such as its parent,
  # its namespace nesting, and the surrounding CallNode (e.g. a method call).
  class NodeContext
    extend T::Sig

    sig { returns(T.nilable(Prism::Node)) }
    attr_reader :node, :parent

    sig { returns(T::Array[String]) }
    attr_reader :nesting

    sig { returns(T.nilable(Prism::CallNode)) }
    attr_reader :call_node

    sig { returns(T.nilable(String)) }
    attr_reader :surrounding_method

    sig do
      params(
        node: T.nilable(Prism::Node),
        parent: T.nilable(Prism::Node),
        nesting_nodes: T::Array[T.any(
          Prism::ClassNode,
          Prism::ModuleNode,
          Prism::SingletonClassNode,
          Prism::DefNode,
          Prism::BlockNode,
          Prism::LambdaNode,
          Prism::ProgramNode,
        )],
        call_node: T.nilable(Prism::CallNode),
      ).void
    end
    def initialize(node, parent, nesting_nodes, call_node)
      @node = node
      @parent = parent
      @nesting_nodes = nesting_nodes
      @call_node = call_node

      nesting, surrounding_method = handle_nesting_nodes(nesting_nodes)
      @nesting = T.let(nesting, T::Array[String])
      @surrounding_method = T.let(surrounding_method, T.nilable(String))
    end

    sig { returns(String) }
    def fully_qualified_name
      @fully_qualified_name ||= T.let(@nesting.join("::"), T.nilable(String))
    end

    sig { returns(T::Array[Symbol]) }
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

    sig do
      params(nodes: T::Array[T.any(
        Prism::ClassNode,
        Prism::ModuleNode,
        Prism::SingletonClassNode,
        Prism::DefNode,
        Prism::BlockNode,
        Prism::LambdaNode,
        Prism::ProgramNode,
      )]).returns([T::Array[String], T.nilable(String)])
    end
    def handle_nesting_nodes(nodes)
      nesting = []
      surrounding_method = T.let(nil, T.nilable(String))

      @nesting_nodes.each do |node|
        case node
        when Prism::ClassNode, Prism::ModuleNode
          nesting << node.constant_path.slice
        when Prism::SingletonClassNode
          nesting << "<Class:#{nesting.flat_map { |n| n.split("::") }.last}>"
        when Prism::DefNode
          surrounding_method = node.name.to_s
          next unless node.receiver.is_a?(Prism::SelfNode)

          nesting << "<Class:#{nesting.flat_map { |n| n.split("::") }.last}>"
        end
      end

      [nesting, surrounding_method]
    end
  end
end
