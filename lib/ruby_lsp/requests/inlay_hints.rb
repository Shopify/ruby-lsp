# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/inlay_hints"

module RubyLsp
  module Requests
    # [Inlay hints](https://microsoft.github.io/language-server-protocol/specification#textDocument_inlayHint)
    # are labels added directly in the code that explicitly show the user something that might
    # otherwise just be implied.
    class InlayHints < Request
      extend T::Sig

      class << self
        extend T::Sig

        sig { returns(Interface::InlayHintOptions) }
        def provider
          Interface::InlayHintOptions.new(resolve_provider: false)
        end
      end

      sig do
        params(
          document: T.any(RubyDocument, ERBDocument),
          hints_configuration: RequestConfig,
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(document, hints_configuration, dispatcher)
        super()

        @response_builder = T.let(
          ResponseBuilders::CollectionResponseBuilder[Interface::InlayHint].new,
          ResponseBuilders::CollectionResponseBuilder[Interface::InlayHint],
        )
        Listeners::InlayHints.new(@response_builder, hints_configuration, dispatcher)
      end

      sig { override.returns(T::Array[Interface::InlayHint]) }
      def perform
        @response_builder.response
      end
    end
  end
end
