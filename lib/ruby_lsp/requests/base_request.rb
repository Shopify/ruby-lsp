# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # :nodoc:
    class BaseRequest < SyntaxTree::Visitor
      extend T::Sig
      extend T::Helpers
      extend T::Generic

      Response = type_template { { upper: T.untyped } }

      abstract!

      sig { overridable.params(document: Document).returns(Response) }
      def self.run(document)
        new(document).run
      end

      sig { params(document: Document).void }
      def initialize(document)
        @document = document

        super()
      end

      sig { abstract.returns(T.untyped) }
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
