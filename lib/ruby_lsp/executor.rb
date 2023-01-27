# typed: strict
# frozen_string_literal: true

module RubyLsp
  # This class dispatches a request execution to the right request class. No IO should happen anywhere here!
  class Executor
    extend T::Sig

    sig { params(store: Store).void }
    def initialize(store)
      # Requests that mutate the store must be run sequentially! Parallel requests only receive a temporary copy of the
      # store
      @store = store
      @notifications = T.let([], T::Array[Notification])
    end

    sig { params(request: T::Hash[Symbol, T.untyped]).returns(Result) }
    def execute(request)
      response = T.let(nil, T.untyped)
      error = T.let(nil, T.nilable(Exception))

      request_time = Benchmark.realtime do
        response = run(request)
      rescue StandardError, LoadError => e
        error = e
      end

      Result.new(response: response, error: error, request_time: request_time, notifications: @notifications)
    end

    private

    sig { params(request: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
    def run(request)
      uri = request.dig(:params, :textDocument, :uri)

      case request[:method]
      when "initialize"
        initialize_request(request.dig(:params))
      when "textDocument/didOpen"
        text_document_did_open(uri, request.dig(:params, :textDocument, :text))
      when "textDocument/didClose"
        @notifications << Notification.new(
          message: "textDocument/publishDiagnostics",
          params: Interface::PublishDiagnosticsParams.new(uri: uri, diagnostics: []),
        )

        text_document_did_close(uri)
      when "textDocument/didChange"
        text_document_did_change(uri, request.dig(:params, :contentChanges))
      when "textDocument/foldingRange"
        folding_range(uri)
      when "textDocument/documentLink"
        document_link(uri)
      when "textDocument/selectionRange"
        selection_range(uri, request.dig(:params, :positions))
      when "textDocument/documentSymbol"
        document_symbol(uri)
      when "textDocument/semanticTokens/full"
        semantic_tokens_full(uri)
      when "textDocument/semanticTokens/range"
        semantic_tokens_range(uri, request.dig(:params, :range))
      when "textDocument/formatting"
        begin
          formatting(uri)
        rescue StandardError => error
          @notifications << Notification.new(
            message: "window/showMessage",
            params: Interface::ShowMessageParams.new(
              type: Constant::MessageType::ERROR,
              message: "Formatting error: #{error.message}",
            ),
          )

          nil
        end
      when "textDocument/documentHighlight"
        document_highlight(uri, request.dig(:params, :position))
      when "textDocument/onTypeFormatting"
        on_type_formatting(uri, request.dig(:params, :position), request.dig(:params, :ch))
      when "hover"
        hover(uri, request.dig(:params, :position))
      when "textDocument/inlayHint"
        inlay_hint(uri, request.dig(:params, :range))
      when "textDocument/codeAction"
        code_action(uri, request.dig(:params, :range))
      when "textDocument/diagnostic"
        begin
          diagnostic(uri)
        rescue StandardError => error
          @notifications << Notification.new(
            message: "window/showMessage",
            params: Interface::ShowMessageParams.new(
              type: Constant::MessageType::ERROR,
              message: "Error running diagnostics: #{error.message}",
            ),
          )

          nil
        end
      end
    end

    sig { params(uri: String).returns(T::Array[Interface::FoldingRange]) }
    def folding_range(uri)
      @store.cache_fetch(uri, :folding_ranges) do |document|
        Requests::FoldingRanges.new(document).run
      end
    end

    sig do
      params(
        uri: String,
        position: Document::PositionShape,
      ).returns(T.nilable(Interface::Hover))
    end
    def hover(uri, position)
      RubyLsp::Requests::Hover.new(@store.get(uri), position).run
    end

    sig { params(uri: String).returns(T::Array[Interface::DocumentLink]) }
    def document_link(uri)
      @store.cache_fetch(uri, :document_link) do |document|
        RubyLsp::Requests::DocumentLink.new(uri, document).run
      end
    end

    sig { params(uri: String).returns(T::Array[Interface::DocumentSymbol]) }
    def document_symbol(uri)
      @store.cache_fetch(uri, :document_symbol) do |document|
        Requests::DocumentSymbol.new(document).run
      end
    end

    sig { params(uri: String, content_changes: T::Array[Document::EditShape]).returns(Object) }
    def text_document_did_change(uri, content_changes)
      @store.push_edits(uri, content_changes)
      VOID
    end

    sig { params(uri: String, text: String).returns(Object) }
    def text_document_did_open(uri, text)
      @store.set(uri, text)
      VOID
    end

    sig { params(uri: String).returns(Object) }
    def text_document_did_close(uri)
      @store.delete(uri)
      VOID
    end

    sig do
      params(
        uri: String,
        positions: T::Array[Document::PositionShape],
      ).returns(T.nilable(T::Array[T.nilable(Requests::Support::SelectionRange)]))
    end
    def selection_range(uri, positions)
      ranges = @store.cache_fetch(uri, :selection_ranges) do |document|
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

    sig { params(uri: String).returns(Interface::SemanticTokens) }
    def semantic_tokens_full(uri)
      @store.cache_fetch(uri, :semantic_highlighting) do |document|
        T.cast(
          Requests::SemanticHighlighting.new(
            document,
            encoder: Requests::Support::SemanticTokenEncoder.new,
          ).run,
          Interface::SemanticTokens,
        )
      end
    end

    sig { params(uri: String).returns(T.nilable(T::Array[Interface::TextEdit])) }
    def formatting(uri)
      Requests::Formatting.new(uri, @store.get(uri)).run
    end

    sig do
      params(
        uri: String,
        position: Document::PositionShape,
        character: String,
      ).returns(T::Array[Interface::TextEdit])
    end
    def on_type_formatting(uri, position, character)
      Requests::OnTypeFormatting.new(@store.get(uri), position, character).run
    end

    sig do
      params(
        uri: String,
        position: Document::PositionShape,
      ).returns(T::Array[Interface::DocumentHighlight])
    end
    def document_highlight(uri, position)
      Requests::DocumentHighlight.new(@store.get(uri), position).run
    end

    sig { params(uri: String, range: Document::RangeShape).returns(T::Array[Interface::InlayHint]) }
    def inlay_hint(uri, range)
      document = @store.get(uri)
      start_line = range.dig(:start, :line)
      end_line = range.dig(:end, :line)

      Requests::InlayHints.new(document, start_line..end_line).run
    end

    sig { params(uri: String, range: Document::RangeShape).returns(T::Array[Interface::CodeAction]) }
    def code_action(uri, range)
      start_line = range.dig(:start, :line)
      end_line = range.dig(:end, :line)
      document = @store.get(uri)

      Requests::CodeActions.new(uri, document, start_line..end_line).run
    end

    sig { params(uri: String).returns(T.nilable(Interface::FullDocumentDiagnosticReport)) }
    def diagnostic(uri)
      response = @store.cache_fetch(uri, :diagnostics) do |document|
        Requests::Diagnostics.new(uri, document).run
      end

      Interface::FullDocumentDiagnosticReport.new(kind: "full", items: response.map(&:to_lsp_diagnostic)) if response
    end

    sig { params(uri: String, range: Document::RangeShape).returns(Interface::SemanticTokens) }
    def semantic_tokens_range(uri, range)
      document = @store.get(uri)
      start_line = range.dig(:start, :line)
      end_line = range.dig(:end, :line)

      T.cast(
        Requests::SemanticHighlighting.new(
          document,
          range: start_line..end_line,
          encoder: Requests::Support::SemanticTokenEncoder.new,
        ).run,
        Interface::SemanticTokens,
      )
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(Interface::InitializeResult) }
    def initialize_request(options)
      @store.clear
      @store.encoding = options.dig(:capabilities, :general, :positionEncodings)
      enabled_features = options.dig(:initializationOptions, :enabledFeatures) || []

      document_symbol_provider = if enabled_features.include?("documentSymbols")
        Interface::DocumentSymbolClientCapabilities.new(
          hierarchical_document_symbol_support: true,
          symbol_kind: {
            value_set: Requests::DocumentSymbol::SYMBOL_KIND.values,
          },
        )
      end

      document_link_provider = if enabled_features.include?("documentLink")
        Interface::DocumentLinkOptions.new(resolve_provider: false)
      end

      hover_provider = if enabled_features.include?("hover")
        Interface::HoverClientCapabilities.new(dynamic_registration: false)
      end

      folding_ranges_provider = if enabled_features.include?("foldingRanges")
        Interface::FoldingRangeClientCapabilities.new(line_folding_only: true)
      end

      semantic_tokens_provider = if enabled_features.include?("semanticHighlighting")
        Interface::SemanticTokensRegistrationOptions.new(
          document_selector: { scheme: "file", language: "ruby" },
          legend: Interface::SemanticTokensLegend.new(
            token_types: Requests::SemanticHighlighting::TOKEN_TYPES.keys,
            token_modifiers: Requests::SemanticHighlighting::TOKEN_MODIFIERS.keys,
          ),
          range: true,
          full: { delta: false },
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
          more_trigger_character: ["\n", "|"],
        )
      end

      inlay_hint_provider = if enabled_features.include?("inlayHint")
        Interface::InlayHintOptions.new(resolve_provider: false)
      end

      Interface::InitializeResult.new(
        capabilities: Interface::ServerCapabilities.new(
          text_document_sync: Interface::TextDocumentSyncOptions.new(
            change: Constant::TextDocumentSyncKind::INCREMENTAL,
            open_close: true,
          ),
          selection_range_provider: enabled_features.include?("selectionRanges"),
          hover_provider: hover_provider,
          document_symbol_provider: document_symbol_provider,
          document_link_provider: document_link_provider,
          folding_range_provider: folding_ranges_provider,
          semantic_tokens_provider: semantic_tokens_provider,
          document_formatting_provider: enabled_features.include?("formatting"),
          document_highlight_provider: enabled_features.include?("documentHighlights"),
          code_action_provider: enabled_features.include?("codeActions"),
          document_on_type_formatting_provider: on_type_formatting_provider,
          diagnostic_provider: diagnostics_provider,
          inlay_hint_provider: inlay_hint_provider,
        ),
      )
    end
  end
end
