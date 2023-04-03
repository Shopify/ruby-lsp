# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Document highlight demo](../../misc/document_highlight.gif)
    #
    # The [document highlight](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentHighlight)
    # informs the editor all relevant elements of the currently pointed item for highlighting. For example, when
    # the cursor is on the `F` of the constant `FOO`, the editor should identify other occurrences of `FOO`
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

      sig { params(document: Document, position: Document::PositionShape).void }
      def initialize(document, position)
        super(document)

        @highlights = T.let([], T::Array[Interface::DocumentHighlight])
        return unless document.parsed?

        @target = T.let(find(position), T.nilable(Support::HighlightTarget))
      end

      sig { override.returns(T.all(T::Array[Interface::DocumentHighlight], Object)) }
      def run
        # no @target means the target is not highlightable
        visit(@document.tree) if @document.parsed? && @target
        @highlights
      end

      sig { override.params(node: T.nilable(SyntaxTree::Node)).void }
      def visit(node)
        return if node.nil?

        match = T.must(@target).highlight_type(node)
        add_highlight(match) if match

        super
      end

      private

      DIRECT_HIGHLIGHTS = T.let(
        [
          SyntaxTree::GVar,
          SyntaxTree::IVar,
          SyntaxTree::Const,
          SyntaxTree::CVar,
          SyntaxTree::VarField,
        ],
        T::Array[T.class_of(SyntaxTree::Node)],
      )

      sig do
        params(
          position: Document::PositionShape,
        ).returns(T.nilable(Support::HighlightTarget))
      end
      def find(position)
        matched, parent = @document.locate_node(position)

        return unless matched && parent
        return unless matched.is_a?(SyntaxTree::Ident) || DIRECT_HIGHLIGHTS.include?(matched.class)

        case matched
        when *DIRECT_HIGHLIGHTS
          Support::HighlightTarget.new(matched)
        when SyntaxTree::Ident
          relevant_node = parent.is_a?(SyntaxTree::Params) ? matched : parent
          Support::HighlightTarget.new(relevant_node)
        end
      end

      sig { params(match: Support::HighlightTarget::HighlightMatch).void }
      def add_highlight(match)
        range = range_from_syntax_tree_node(match.node)
        @highlights << Interface::DocumentHighlight.new(range: range, kind: match.type)
      end
    end
  end
end
