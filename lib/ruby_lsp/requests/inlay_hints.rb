# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/inlay_hints"

module RubyLsp
  module Requests
    # [Inlay hints](https://microsoft.github.io/language-server-protocol/specification#textDocument_inlayHint)
    # are labels added directly in the code that explicitly show the user something that might
    # otherwise just be implied.
    class InlayHints < Request
      class << self
        #: -> Interface::InlayHintOptions
        def provider
          Interface::InlayHintOptions.new(resolve_provider: false)
        end
      end

      #: (GlobalState, (RubyDocument | ERBDocument), Prism::Dispatcher) -> void
      def initialize(global_state, document, dispatcher)
        super()

        @response_builder = ResponseBuilders::CollectionResponseBuilder
          .new #: ResponseBuilders::CollectionResponseBuilder[Interface::InlayHint]
        Listeners::InlayHints.new(global_state, @response_builder, dispatcher)
      end

      # @override
      #: -> Array[Interface::InlayHint]
      def perform
        @response_builder.response
      end
    end
  end
end
