# typed: strict
# frozen_string_literal: true

module RubyLsp
  # This class allows listeners to access contextual information about a node in the AST, such as its parent
  # and its namespace nesting.
  class NodeContext
    extend T::Sig

    sig { returns(T.nilable(Prism::Node)) }
    attr_reader :node, :parent

    sig { returns(T::Array[String]) }
    attr_reader :nesting

    sig { params(node: T.nilable(Prism::Node), parent: T.nilable(Prism::Node), nesting: T::Array[String]).void }
    def initialize(node, parent, nesting)
      @node = node
      @parent = parent
      @nesting = nesting
    end

    sig { returns(String) }
    def fully_qualified_name
      @fully_qualified_name ||= T.let(@nesting.join("::"), T.nilable(String))
    end
  end
end
