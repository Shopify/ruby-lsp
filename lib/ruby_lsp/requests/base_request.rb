# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # :nodoc:
    class BaseRequest < SyntaxTree::Visitor
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { params(document: Document).void }
      def initialize(document)
        @document = document

        super()
      end

      sig { abstract.returns(Object) }
      def run; end

      sig { params(node: SyntaxTree::Node).returns(LanguageServer::Protocol::Interface::Range) }
      def range_from_syntax_tree_node(node)
        loc = node.location

        LanguageServer::Protocol::Interface::Range.new(
          start: LanguageServer::Protocol::Interface::Position.new(line: loc.start_line - 1,
            character: loc.start_column),
          end: LanguageServer::Protocol::Interface::Position.new(line: loc.end_line - 1, character: loc.end_column),
        )
      end
    end
  end
end
