# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/inlay_hints"

module RubyLsp
  module Requests
    # ![Inlay hint demo](../../inlay_hints.gif)
    #
    # [Inlay hints](https://microsoft.github.io/language-server-protocol/specification#textDocument_inlayHint)
    # are labels added directly in the code that explicitly show the user something that might
    # otherwise just be implied.
    #
    # # Configuration
    #
    # To enable rescue hints, set `rubyLsp.featuresConfiguration.inlayHint.implicitRescue` to `true`.
    #
    # To enable hash value hints, set `rubyLsp.featuresConfiguration.inlayHint.implicitHashValue` to `true`.
    #
    # To enable all hints, set `rubyLsp.featuresConfiguration.inlayHint.enableAll` to `true`.
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
    #
    # # Example
    #
    # ```ruby
    # var = "foo"
    # {
    #   var: var, # Label "var" goes here in cases where the value is omitted
    #   a: "hello",
    # }
    # ```
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
          document: Document,
          range: T::Hash[Symbol, T.untyped],
          hints_configuration: RequestConfig,
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(document, range, hints_configuration, dispatcher)
        super()
        start_line = range.dig(:start, :line)
        end_line = range.dig(:end, :line)

        @response_builder = T.let(
          ResponseBuilders::CollectionResponseBuilder[Interface::InlayHint].new,
          ResponseBuilders::CollectionResponseBuilder[Interface::InlayHint],
        )
        Listeners::InlayHints.new(@response_builder, start_line..end_line, hints_configuration, dispatcher)
      end

      sig { override.returns(T::Array[Interface::InlayHint]) }
      def perform
        @response_builder.response
      end
    end
  end
end
