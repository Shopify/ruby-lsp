# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Inlay hint demo](../../inlay_hints.gif)
    #
    # [Inlay hints](https://microsoft.github.io/language-server-protocol/specification#textDocument_inlayHint)
    # are labels added directly in the code that explicitly show the user something that might
    # otherwise just be implied.
    #
    # # Example
    #
    # ```ruby
    # begin
    #   puts "do something that might raise"
    # rescue # Label "StandardError" goes here as a bare rescue implies rescuing StandardError
    #   puts "handle some rescue"
    # end
    # ```
    class InlayHints < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T::Array[Interface::InlayHint] } }

      RESCUE_STRING_LENGTH = T.let("rescue".length, Integer)

      sig { override.returns(ResponseType) }
      attr_reader :_response

      sig { params(range: T::Range[Integer], dispatcher: Prism::Dispatcher, message_queue: Thread::Queue).void }
      def initialize(range, dispatcher, message_queue)
        super(dispatcher, message_queue)

        @_response = T.let([], ResponseType)
        @range = range

        dispatcher.register(self, :on_rescue_node_enter)
      end

      sig { params(node: Prism::RescueNode).void }
      def on_rescue_node_enter(node)
        return unless node.exceptions.empty?

        loc = node.location
        return unless visible?(node, @range)

        @_response << Interface::InlayHint.new(
          position: { line: loc.start_line - 1, character: loc.start_column + RESCUE_STRING_LENGTH },
          label: "StandardError",
          padding_left: true,
          tooltip: "StandardError is implied in a bare rescue",
        )
      end
    end
  end
end
