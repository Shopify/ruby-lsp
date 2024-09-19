# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [code actions](https://microsoft.github.io/language-server-protocol/specification#textDocument_codeAction)
    # request informs the editor of RuboCop quick fixes that can be applied. These are accessible by hovering over a
    # specific diagnostic.
    class CodeActions < Request
      extend T::Sig

      EXTRACT_TO_VARIABLE_TITLE = "Refactor: Extract Variable"
      EXTRACT_TO_METHOD_TITLE = "Refactor: Extract Method"
      TOGGLE_BLOCK_STYLE_TITLE = "Refactor: Toggle block style"

      class << self
        extend T::Sig

        sig { returns(Interface::CodeActionRegistrationOptions) }
        def provider
          Interface::CodeActionRegistrationOptions.new(
            document_selector: [Interface::DocumentFilter.new(language: "ruby")],
            resolve_provider: true,
          )
        end
      end

      sig do
        params(
          document: T.any(RubyDocument, ERBDocument),
          range: T::Hash[Symbol, T.untyped],
          context: T::Hash[Symbol, T.untyped],
        ).void
      end
      def initialize(document, range, context)
        super()
        @document = document
        @uri = T.let(document.uri, URI::Generic)
        @range = range
        @context = context
      end

      sig { override.returns(T.nilable(T.all(T::Array[Interface::CodeAction], Object))) }
      def perform
        diagnostics = @context[:diagnostics]

        code_actions = diagnostics.flat_map do |diagnostic|
          diagnostic.dig(:data, :code_actions) || []
        end

        # Only add refactor actions if there's a non empty selection in the editor
        unless @range.dig(:start) == @range.dig(:end)
          code_actions << Interface::CodeAction.new(
            title: EXTRACT_TO_VARIABLE_TITLE,
            kind: Constant::CodeActionKind::REFACTOR_EXTRACT,
            data: { range: @range, uri: @uri.to_s },
          )
          code_actions << Interface::CodeAction.new(
            title: EXTRACT_TO_METHOD_TITLE,
            kind: Constant::CodeActionKind::REFACTOR_EXTRACT,
            data: { range: @range, uri: @uri.to_s },
          )
          code_actions << Interface::CodeAction.new(
            title: TOGGLE_BLOCK_STYLE_TITLE,
            kind: Constant::CodeActionKind::REFACTOR_REWRITE,
            data: { range: @range, uri: @uri.to_s },
          )
        end

        code_actions
      end
    end
  end
end
