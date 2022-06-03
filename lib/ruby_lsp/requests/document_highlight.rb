# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [document highlight](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentHighlight)
    # informs the editor all relevant elements of the currently pointed item for highlighting. For example, when
    # the cursor is on the `F` of the constant `FOO`, the editor should identify other occurences of `FOO`
    # and highlight them.
    #
    # For writable elements like constants or variables, their read/write occurrences should be highlighted differently.
    # This is achieved by sending different "kind" attributes to the editor (2 for read and 3 for write).
    #
    # # Example
    #
    # ```ruby
    # FOO = 1 # should be highlighted as "write"
    #
    # def foo
    #   FOO # should be highlighted as "read"
    # end
    # ```
    class DocumentHighlight < BaseRequest
      extend T::Sig
      extend T::Generic

      Response = type_template { { fixed: T::Array[LanguageServer::Protocol::Interface::DocumentHighlight] } }

      VarNodes = T.type_alias do
        T.any(
          SyntaxTree::GVar,
          SyntaxTree::Ident,
          SyntaxTree::IVar,
          SyntaxTree::Const,
          SyntaxTree::CVar
        )
      end

      sig do
        override(allow_incompatible: true).params(
          document: Document,
          position: Document::PositionShape
        ).returns(Response)
      end
      def self.run(document, position)
        new(document, position).run
      end

      sig { params(document: Document, position: Document::PositionShape).void }
      def initialize(document, position)
        @highlights = T.let([], T::Array[LanguageServer::Protocol::Interface::DocumentHighlight])
        position = Document::Scanner.new(document.source).find_position(position)
        @target = T.let(find(document.tree, position), T.nilable(VarNodes))

        super(document)
      end

      sig { override.returns(T::Array[LanguageServer::Protocol::Interface::DocumentHighlight]) }
      def run
        # no @target means the target is not highlightable
        return [] unless @target

        visit(@document.tree)
        @highlights
      end

      sig { params(node: SyntaxTree::VarField).void }
      def visit_var_field(node)
        if matches_target?(node.value)
          add_highlight(
            node.value,
            LanguageServer::Protocol::Constant::DocumentHighlightKind::WRITE
          )
        end

        super
      end

      sig { params(node: SyntaxTree::VarRef).void }
      def visit_var_ref(node)
        if matches_target?(node.value)
          add_highlight(
            node.value,
            LanguageServer::Protocol::Constant::DocumentHighlightKind::READ
          )
        end

        super
      end

      private

      sig { params(node: SyntaxTree::Node, position: Integer).returns(T.nilable(VarNodes)) }
      def find(node, position)
        matched =
          node.child_nodes.compact.bsearch do |child|
            if (child.location.start_char...child.location.end_char).cover?(position)
              0
            else
              position <=> child.location.start_char
            end
          end

        case matched
        when SyntaxTree::GVar, SyntaxTree::Ident, SyntaxTree::IVar, SyntaxTree::Const, SyntaxTree::CVar
          matched
        when SyntaxTree::Node
          find(matched, position)
        end
      end

      sig { params(node: SyntaxTree::Node).returns(T::Boolean) }
      def matches_target?(node)
        node.is_a?(@target.class) && T.cast(node, VarNodes).value == T.must(@target).value
      end

      sig { params(node: SyntaxTree::Node, kind: Integer).void }
      def add_highlight(node, kind)
        range = range_from_syntax_tree_node(node)
        @highlights << LanguageServer::Protocol::Interface::DocumentHighlight.new(range: range, kind: kind)
      end
    end
  end
end
