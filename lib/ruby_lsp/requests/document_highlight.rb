# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Document highlight demo](../../document_highlight.gif)
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
    class DocumentHighlight < Listener
      extend T::Sig

      ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

      sig { override.returns(ResponseType) }
      attr_reader :_response

      sig do
        params(
          target: T.nilable(SyntaxTree::Node),
          parent: T.nilable(SyntaxTree::Node),
          emitter: EventEmitter,
          message_queue: Thread::Queue,
        ).void
      end
      def initialize(target, parent, emitter, message_queue)
        super(emitter, message_queue)

        @_response = T.let([], T::Array[Interface::DocumentHighlight])

        return unless target && parent

        highlight_target =
          case target
          when *DIRECT_HIGHLIGHTS
            Support::HighlightTarget.new(target)
          when SyntaxTree::Ident
            relevant_node = parent.is_a?(SyntaxTree::Params) ? target : parent
            Support::HighlightTarget.new(relevant_node)
          end

        @target = T.let(highlight_target, T.nilable(Support::HighlightTarget))

        emitter.register(self, :on_node) if @target
      end

      sig { params(node: T.nilable(SyntaxTree::Node)).void }
      def on_node(node)
        return if node.nil?

        match = T.must(@target).highlight_type(node)
        add_highlight(match) if match
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

      sig { params(match: Support::HighlightTarget::HighlightMatch).void }
      def add_highlight(match)
        range = range_from_syntax_tree_node(match.node)
        @_response << Interface::DocumentHighlight.new(range: range, kind: match.type)
      end
    end
  end
end
