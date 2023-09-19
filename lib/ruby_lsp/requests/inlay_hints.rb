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

      sig { params(range: T::Range[Integer], emitter: EventEmitter, message_queue: Thread::Queue).void }
      def initialize(range, emitter, message_queue)
        super(emitter, message_queue)

        @_response = T.let([], ResponseType)
        @range = range

        emitter.register(self, :on_rescue)
      end

      sig { params(node: YARP::RescueNode).void }
      def on_rescue(node)
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
