# typed: strict
# frozen_string_literal: true

module RubyLsp
  class NodeContext
    extend T::Sig

    sig { returns(T.nilable(Prism::Node)) }
    attr_reader :closest, :parent

    sig { returns(T::Array[String]) }
    attr_reader :nesting

    sig { params(closest: T.nilable(Prism::Node), parent: T.nilable(Prism::Node), nesting: T::Array[String]).void }
    def initialize(closest, parent, nesting)
      @closest = closest
      @parent = parent
      @nesting = nesting
    end
  end
end
