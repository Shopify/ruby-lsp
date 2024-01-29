# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class DocumentHighlight < ResponseBuilder
      ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

      extend T::Sig

      sig { void }
      def initialize
        super
        @highlights = T.let([], ResponseType)
      end

      sig { params(highlight: Interface::DocumentHighlight).void }
      def <<(highlight)
        @highlights << highlight
      end

      sig { override.returns(ResponseType) }
      def response
        @highlights
      end
    end
  end
end
