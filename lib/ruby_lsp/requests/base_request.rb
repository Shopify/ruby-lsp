# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # :nodoc:
    class BaseRequest < YARP::Visitor
      extend T::Sig
      extend T::Helpers
      include Support::Common

      abstract!

      sig { params(document: Document).void }
      def initialize(document)
        @document = document
        super()
      end

      sig { abstract.returns(Object) }
      def run; end

      # YARP implements `visit_all` using `map` instead of `each` for users who want to use the pattern
      # `result = visitor.visit(tree)`. However, we don't use that pattern and should avoid producing a new array for
      # every single node visited
      sig { params(nodes: T::Array[T.nilable(YARP::Node)]).void }
      def visit_all(nodes)
        nodes.each { |node| visit(node) }
      end
    end
  end
end
