# typed: strict
# frozen_string_literal: true

require "shellwords"

require "ruby_lsp/listeners/code_lens"

module RubyLsp
  module Requests
    # The
    # [code lens](https://microsoft.github.io/language-server-protocol/specification#textDocument_codeLens)
    # request informs the editor of runnable commands such as testing and debugging.
    class CodeLens < Request
      extend T::Sig

      class << self
        extend T::Sig

        sig { returns(Interface::CodeLensOptions) }
        def provider
          Interface::CodeLensOptions.new(resolve_provider: false)
        end
      end

      sig do
        params(
          uri: URI::Generic,
          document: RubyLsp::RubyDocument,
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(uri, document, dispatcher)
        @response_builder = T.let(
          ResponseBuilders::CollectionResponseBuilder[Interface::CodeLens].new,
          ResponseBuilders::CollectionResponseBuilder[Interface::CodeLens],
        )
        super()
        Listeners::CodeLens.new(@response_builder, document, dispatcher)

        Addon.addons.each do |addon|
          addon.create_code_lens_listener(@response_builder, document, dispatcher)
        end
      end

      sig { override.returns(T::Array[Interface::CodeLens]) }
      def perform
        @response_builder.response
      end
    end
  end
end
