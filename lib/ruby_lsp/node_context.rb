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

    sig do
      params(
        node: T.nilable(Prism::Node),
        parent: T.nilable(Prism::Node),
        nesting: T::Array[String],
        call_node: T.nilable(Prism::CallNode),
      ).void
    end
    def initialize(node, parent, nesting, call_node)
      @node = node
      @parent = parent
      @nesting = nesting
      @call_node = call_node
    end

    sig { returns(String) }
    def fully_qualified_name
      @fully_qualified_name ||= T.let(@nesting.join("::"), T.nilable(String))
    end
  end
end
