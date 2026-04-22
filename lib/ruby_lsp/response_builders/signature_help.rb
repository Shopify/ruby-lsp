# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    #: [ResponseType = Interface::SignatureHelp?]
    class SignatureHelp < ResponseBuilder
      #: (Encoding, Prism::ParseLexResult) -> void
      def initialize(encoding, parse_result)
        super
        @signature_help = nil #: ResponseType
      end

      #: (ResponseType signature_help) -> void
      def replace(signature_help)
        @signature_help = signature_help
      end

      # @override
      #: -> ResponseType
      def response
        @signature_help
      end
    end
  end
end
