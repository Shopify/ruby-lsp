# typed: strict
# frozen_string_literal: true

require "ruby_lsp/internal"

module RubyLsp
  Handler.start do
    on("initialize") do |request|
      store.clear
      initialization_options = request.dig(:params, :initializationOptions)
      enabled_features = initialization_options.fetch(:enabledFeatures, [])

      document_symbol_provider = if enabled_features.include?("documentSymbols")
        Interface::DocumentSymbolClientCapabilities.new(
          hierarchical_document_symbol_support: true,
          symbol_kind: {
            value_set: Requests::DocumentSymbol::SYMBOL_KIND.values,
          }
        )
      end

      document_link_provider = if enabled_features.include?("documentLink")
        Interface::DocumentLinkOptions.new(resolve_provider: false)
      end

      folding_ranges_provider = if enabled_features.include?("foldingRanges")
        Interface::FoldingRangeClientCapabilities.new(line_folding_only: true)
      end

      semantic_tokens_provider = if enabled_features.include?("semanticHighlighting")
        Interface::SemanticTokensRegistrationOptions.new(
          document_selector: { scheme: "file", language: "ruby" },
          legend: Interface::SemanticTokensLegend.new(
            token_types: Requests::SemanticHighlighting::TOKEN_TYPES.keys,
            token_modifiers: Requests::SemanticHighlighting::TOKEN_MODIFIERS.keys
          ),
          range: false,
          full: {
            delta: true,
          }
        )
      end

      diagnostics_provider = if enabled_features.include?("diagnostics")
        {
          interFileDependencies: false,
          workspaceDiagnostics: false,
        }
      end

      on_type_formatting_provider = if enabled_features.include?("onTypeFormatting")
        Interface::DocumentOnTypeFormattingOptions.new(
          first_trigger_character: "{",
          more_trigger_character: ["\n", "|"]
        )
      end

      Interface::InitializeResult.new(
        capabilities: Interface::ServerCapabilities.new(
          text_document_sync: Interface::TextDocumentSyncOptions.new(
            change: Constant::TextDocumentSyncKind::INCREMENTAL,
            open_close: true,
          ),
          selection_range_provider: enabled_features.include?("selectionRanges"),
          document_symbol_provider: document_symbol_provider,
          document_link_provider: document_link_provider,
          folding_range_provider: folding_ranges_provider,
          semantic_tokens_provider: semantic_tokens_provider,
          document_formatting_provider: enabled_features.include?("formatting"),
          document_highlight_provider: enabled_features.include?("documentHighlights"),
          code_action_provider: enabled_features.include?("codeActions"),
          document_on_type_formatting_provider: on_type_formatting_provider,
          diagnostic_provider: diagnostics_provider,
        )
      )
    end

    on("textDocument/didChange") do |request|
      uri = request.dig(:params, :textDocument, :uri)
      store.push_edits(uri, request.dig(:params, :contentChanges))

      Handler::VOID
    end

    on("textDocument/didOpen") do |request|
      uri = request.dig(:params, :textDocument, :uri)
      text = request.dig(:params, :textDocument, :text)
      store.set(uri, text)

      Handler::VOID
    end

    on("textDocument/didClose") do |request|
      uri = request.dig(:params, :textDocument, :uri)
      store.delete(uri)
      clear_diagnostics(uri)

      Handler::VOID
    end

    on("textDocument/documentSymbol", parallel: true) do |request|
      store.cache_fetch(request.dig(:params, :textDocument, :uri), :document_symbol) do |document|
        Requests::DocumentSymbol.new(document).run
      end
    end

    on("textDocument/documentLink", parallel: true) do |request|
      uri = request.dig(:params, :textDocument, :uri)
      store.cache_fetch(uri, :document_link) do |document|
        RubyLsp::Requests::DocumentLink.new(uri, document).run
      end
    end

    on("textDocument/foldingRange", parallel: true) do |request|
      store.cache_fetch(request.dig(:params, :textDocument, :uri), :folding_ranges) do |document|
        Requests::FoldingRanges.new(document).run
      end
    end

    on("textDocument/selectionRange", parallel: true) do |request|
      uri = request.dig(:params, :textDocument, :uri)
      positions = request.dig(:params, :positions)

      ranges = store.cache_fetch(uri, :selection_ranges) do |document|
        Requests::SelectionRanges.new(document).run
      end

      # Per the selection range request spec (https://microsoft.github.io/language-server-protocol/specification#textDocument_selectionRange),
      # every position in the positions array should have an element at the same index in the response
      # array. For positions without a valid selection range, the corresponding element in the response
      # array will be nil.

      unless ranges.nil?
        positions.map do |position|
          ranges.find do |range|
            range.cover?(position)
          end
        end
      end
    end

    on("textDocument/semanticTokens/full", parallel: true) do |request|
      store.cache_fetch(request.dig(:params, :textDocument, :uri), :semantic_highlighting) do |document|
        T.cast(
          Requests::SemanticHighlighting.new(
            document,
            encoder: Requests::Support::SemanticTokenEncoder.new
          ).run,
          LanguageServer::Protocol::Interface::SemanticTokens
        )
      end
    end

    on("textDocument/formatting", parallel: true) do |request|
      uri = request.dig(:params, :textDocument, :uri)

      Requests::Formatting.new(uri, store.get(uri)).run
    rescue RuboCop::Runner::InfiniteCorrectionLoop => e
      show_message(Constant::MessageType::ERROR, "Error from RuboCop: #{e.message}")
      nil
    end

    on("textDocument/onTypeFormatting", parallel: true) do |request|
      uri = request.dig(:params, :textDocument, :uri)
      position = request.dig(:params, :position)
      character = request.dig(:params, :ch)

      Requests::OnTypeFormatting.new(store.get(uri), position, character).run
    end

    on("textDocument/documentHighlight", parallel: true) do |request|
      document = store.get(request.dig(:params, :textDocument, :uri))

      if document.parsed?
        Requests::DocumentHighlight.new(document, request.dig(:params, :position)).run
      end
    end

    on("textDocument/codeAction", parallel: true) do |request|
      uri = request.dig(:params, :textDocument, :uri)
      range = request.dig(:params, :range)
      start_line = range.dig(:start, :line)
      end_line = range.dig(:end, :line)

      store.cache_fetch(uri, :code_actions) do |document|
        Requests::CodeActions.new(uri, document, start_line..end_line).run
      end
    end

    on("$/cancelRequest") do |request|
      cancel_request(request[:params][:id])
      Handler::VOID
    end

    on("textDocument/diagnostic") do |request|
      uri = request.dig(:params, :textDocument, :uri)
      response = store.cache_fetch(uri, :diagnostics) do |document|
        Requests::Diagnostics.new(uri, document).run
      end

      { kind: "full", items: response.map(&:to_lsp_diagnostic) } if response
    end.on_error do |error|
      if error.is_a?(RuboCop::ValidationError)
        show_message(Constant::MessageType::ERROR, "Error in RuboCop configuration file: #{error.message}")
      end
    end

    on("shutdown") { shutdown }

    on("exit") do
      # We return zero if shutdown has already been received or one otherwise as per the recommendation in the spec
      # https://microsoft.github.io/language-server-protocol/specification/#exit
      status = store.empty? ? 0 : 1
      exit(status)
    end
  end
end
