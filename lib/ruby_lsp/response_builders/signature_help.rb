# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class SignatureHelp < ResponseBuilder
      extend T::Sig

      ResponseType = type_member { { fixed: T.nilable(Interface::SignatureHelp) } }

      sig { void }
      def initialize
        super
        @signature_help = T.let(nil, ResponseType)
      end

      sig { params(signature_help: ResponseType).void }
      def replace(signature_help)
        @signature_help = signature_help
      end

      sig { override.returns(ResponseType) }
      def response
        @signature_help
      end
    end
  end
end
