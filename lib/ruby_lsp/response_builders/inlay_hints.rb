# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class InlayHints < ResponseBuilder
      ResponseType = type_member { { fixed: T::Array[Interface::InlayHint] } }

      extend T::Sig

      sig { void }
      def initialize
        super
        @inlay_hints = T.let([], ResponseType)
      end

      sig { params(inlay_hint: Interface::InlayHint).void }
      def <<(inlay_hint)
        @inlay_hints << inlay_hint
      end

      sig { override.returns(ResponseType) }
      def response
        @inlay_hints
      end
    end
  end
end
