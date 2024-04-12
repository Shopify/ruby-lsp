# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/semantic_highlighting"

module RubyLsp
  module Requests
    # ![Semantic highlighting demo](../../semantic_highlighting.gif)
    #
    # The [semantic
    # highlighting](https://microsoft.github.io/language-server-protocol/specification#textDocument_semanticTokens)
    # request informs the editor of the correct token types to provide consistent and accurate highlighting for themes.
    #
    # # Example
    #
    # ```ruby
    # def foo
    #   var = 1 # --> semantic highlighting: local variable
    #   some_invocation # --> semantic highlighting: method invocation
    #   var # --> semantic highlighting: local variable
    # end
    # ```
    class SemanticHighlighting < Request
      extend T::Sig

      class << self
        extend T::Sig

        sig { returns(Interface::SemanticTokensRegistrationOptions) }
        def provider
          Interface::SemanticTokensRegistrationOptions.new(
            document_selector: [{ language: "ruby" }],
            legend: Interface::SemanticTokensLegend.new(
              token_types: ResponseBuilders::SemanticHighlighting::TOKEN_TYPES.keys,
              token_modifiers: ResponseBuilders::SemanticHighlighting::TOKEN_MODIFIERS.keys,
            ),
            range: true,
            full: { delta: false },
          )
        end
      end

      sig { params(global_state: GlobalState, dispatcher: Prism::Dispatcher, range: T.nilable(T::Range[Integer])).void }
      def initialize(global_state, dispatcher, range: nil)
        super()
        @response_builder = T.let(
          ResponseBuilders::SemanticHighlighting.new(global_state.encoding),
          ResponseBuilders::SemanticHighlighting,
        )
        Listeners::SemanticHighlighting.new(dispatcher, @response_builder, range: range)

        Addon.addons.each do |addon|
          addon.create_semantic_highlighting_listener(@response_builder, dispatcher)
        end
      end

      sig { override.returns(Interface::SemanticTokens) }
      def perform
        @response_builder.response
      end
    end
  end
end
