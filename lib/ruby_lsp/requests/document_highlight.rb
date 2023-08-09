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
      attr_reader :response

      sig do
        params(
          target: T.nilable(YARP::Node),
          parent: T.nilable(YARP::Node),
          emitter: EventEmitter,
          message_queue: Thread::Queue,
        ).void
      end
      def initialize(target, parent, emitter, message_queue)
        super(emitter, message_queue)

        @response = T.let([], T::Array[Interface::DocumentHighlight])

        return unless target && parent

        highlight_target =
          case target
          when *DIRECT_HIGHLIGHTS
            Support::HighlightTarget.new(target)
          when YARP::GlobalVariableWriteNode # , InstanceVariableWriteNode, ConstantWriteNode, ClassVariableWriteNode
            Support::HighlightTarget.new(target)

          # when SyntaxTree::Ident
          #   relevant_node = parent.is_a?(YARP::ParametersNode) ? target : parent
          #   Support::HighlightTarget.new(relevant_node)
          end

        @target = T.let(highlight_target, T.nilable(Support::HighlightTarget))

        emitter.register(self, :on_node) if @target
      end

      sig { params(node: T.nilable(YARP::Node)).void }
      def on_node(node)
        return if node.nil?

        match = T.must(@target).highlight_type(node)
        add_highlight(match) if match
      end

      private

      DIRECT_HIGHLIGHTS = T.let(
        [
          YARP::GlobalVariableReadNode,
          YARP::InstanceVariableReadNode,
          YARP::ConstantReadNode,
          YARP::ClassVariableReadNode,
          # YARP::VarField,
        ],
        T::Array[T.class_of(YARP::Node)],
      )

      sig { params(match: Support::HighlightTarget::HighlightMatch).void }
      def add_highlight(match)
        range = range_from_syntax_tree_node(match.node)
        @response << Interface::DocumentHighlight.new(range: range, kind: match.type)
      end
    end
  end
end
