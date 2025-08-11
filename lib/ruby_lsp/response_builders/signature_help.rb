# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    #: [ResponseType = Interface::SignatureHelp?]
    class SignatureHelp < ResponseBuilder
      #: -> void
      def initialize
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
