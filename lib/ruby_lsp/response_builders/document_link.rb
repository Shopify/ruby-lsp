# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class DocumentLink < ResponseBuilder
      ResponseType = type_member { { fixed: T::Array[Interface::DocumentLink] } }

      extend T::Sig

      sig { void }
      def initialize
        super
        @links = T.let([], ResponseType)
      end

      sig { params(link: Interface::DocumentLink).void }
      def <<(link)
        @links << link
      end

      sig { override.returns(ResponseType) }
      def response
        @links
      end
    end
  end
end
