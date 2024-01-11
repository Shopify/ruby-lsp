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
      extend T::Generic

      ResponseType = type_member { { fixed: T::Array[Listeners::SemanticHighlighting::SemanticToken] } }

      class << self
        extend T::Sig

        sig { returns(Interface::SemanticTokensRegistrationOptions) }
        def provider
          Interface::SemanticTokensRegistrationOptions.new(
            document_selector: { scheme: "file", language: "ruby" },
            legend: Interface::SemanticTokensLegend.new(
              token_types: Listeners::SemanticHighlighting::TOKEN_TYPES.keys,
              token_modifiers: Listeners::SemanticHighlighting::TOKEN_MODIFIERS.keys,
            ),
            range: true,
            full: { delta: false },
          )
        end
      end

      sig { params(dispatcher: Prism::Dispatcher, range: T.nilable(T::Range[Integer])).void }
      def initialize(dispatcher, range: nil)
        super()
        @listener = T.let(Listeners::SemanticHighlighting.new(dispatcher, range: range), Listener[ResponseType])
      end

      sig { override.returns(ResponseType) }
      def perform
        @listener.response
      end
    end
  end
end
