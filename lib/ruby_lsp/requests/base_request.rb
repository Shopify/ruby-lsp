# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # :nodoc:
    class BaseRequest < SyntaxTree::Visitor
      extend T::Sig
      extend T::Helpers
      include Support::Common

      abstract!

      # We must accept rest keyword arguments here, so that the argument count matches when
      # SyntaxTree::WithScope#initialize invokes `super` for Sorbet. We don't actually use these parameters for
      # anything. We can remove these arguments once we drop support for Ruby 2.7
      # https://github.com/ruby-syntax-tree/syntax_tree/blob/4dac90b53df388f726dce50ce638a1ba71cc59f8/lib/syntax_tree/with_scope.rb#L122
      sig { params(document: Document, _kwargs: T.untyped).void }
      def initialize(document, **_kwargs)
        @document = document

        # Parsing the document here means we're taking a lazy approach by only doing it when the first feature request
        # is received by the server. This happens because {Document#parse} remembers if there are new edits to be parsed
        @document.parse

        super()
      end

      sig { abstract.returns(Object) }
      def run; end

      # Syntax Tree implements `visit_all` using `map` instead of `each` for users who want to use the pattern
      # `result = visitor.visit(tree)`. However, we don't use that pattern and should avoid producing a new array for
      # every single node visited
      sig { params(nodes: T::Array[T.nilable(SyntaxTree::Node)]).void }
      def visit_all(nodes)
        nodes.each { |node| visit(node) }
      end
    end
  end
end
