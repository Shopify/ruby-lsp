# typed: false
# frozen_string_literal: true

require "ruby_lsp/requests"
require "ruby_lsp/store"
require "benchmark"

module RubyLsp
  class Handler
    VOID = Object.new.freeze

    attr_reader :store

    Interface = LanguageServer::Protocol::Interface
    Constant = LanguageServer::Protocol::Constant
    Transport = LanguageServer::Protocol::Transport

    def initialize
      @writer = Transport::Stdio::Writer.new
      @reader = Transport::Stdio::Reader.new
      @handlers = {}
      @store = Store.new
    end

    def start
      $stderr.puts "Starting Ruby LSP..."
      @reader.read do |request|
        with_telemetry(request) { handle(request) }
      end
    end

    def config(&blk)
      instance_exec(&blk)
    end

    private

    def on(msg, &blk)
      @handlers[msg.to_s] = blk
    end

    def handle(request)
      handler = @handlers[request[:method]]
      return unless handler

      result = handler.call(request)
      @writer.write(id: request[:id], result: result) unless result == VOID
    end

    def shutdown
      $stderr.puts "Shutting down Ruby LSP..."
      store.clear
    end

    def respond_with_capabilities(enabled_features)
      document_symbol_provider = if enabled_features.include?("documentSymbols")
        Interface::DocumentSymbolClientCapabilities.new(
          hierarchical_document_symbol_support: true,
          symbol_kind: {
            value_set: Requests::DocumentSymbol::SYMBOL_KIND.values,
          }
        )
      end

      folding_ranges_provider = if enabled_features.include?("foldingRanges")
        Interface::FoldingRangeClientCapabilities.new(line_folding_only: true)
      end

      semantic_tokens_provider = if enabled_features.include?("semanticHighlighting")
        Interface::SemanticTokensRegistrationOptions.new(
          document_selector: { scheme: "file", language: "ruby" },
          legend: Interface::SemanticTokensLegend.new(
            token_types: Requests::SemanticHighlighting::TOKEN_TYPES,
            token_modifiers: Requests::SemanticHighlighting::TOKEN_MODIFIERS
          ),
          range: false,
          full: {
            delta: true,
          }
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
          folding_range_provider: folding_ranges_provider,
          semantic_tokens_provider: semantic_tokens_provider,
          document_formatting_provider: enabled_features.include?("formatting"),
          document_highlight_provider: enabled_features.include?("documentHighlights"),
          code_action_provider: enabled_features.include?("codeActions")
        )
      )
    end

    def respond_with_document_symbol(uri)
      store.cache_fetch(uri, :document_symbol) do |document|
        RubyLsp::Requests::DocumentSymbol.run(document)
      end
    end

    def respond_with_folding_ranges(uri)
      store.cache_fetch(uri, :folding_ranges) do |document|
        Requests::FoldingRanges.run(document)
      end
    end

    def respond_with_selection_ranges(uri, positions)
      ranges = store.cache_fetch(uri, :selection_ranges) do |document|
        Requests::SelectionRanges.run(document)
      end

      # Per the selection range request spec (https://microsoft.github.io/language-server-protocol/specification#textDocument_selectionRange),
      # every position in the positions array should have an element at the same index in the response
      # array. For positions without a valid selection range, the corresponding element in the response
      # array will be nil.
      positions.map do |position|
        ranges.find do |range|
          range.cover?(position)
        end
      end
    end

    def respond_with_semantic_highlighting(uri)
      store.cache_fetch(uri, :semantic_highlighting) do |document|
        Requests::SemanticHighlighting.new(document, encoder: Requests::Support::SemanticTokenEncoder.new).run
      end
    end

    def respond_with_formatting(uri)
      Requests::Formatting.run(uri, store.get(uri))
    end

    def send_diagnostics(uri)
      response = store.cache_fetch(uri, :diagnostics) do |document|
        Requests::Diagnostics.run(uri, document)
      end

      @writer.write(
        method: "textDocument/publishDiagnostics",
        params: Interface::PublishDiagnosticsParams.new(
          uri: uri,
          diagnostics: response.map(&:to_lsp_diagnostic)
        )
      )
    end

    def respond_with_code_actions(uri, range)
      store.cache_fetch(uri, :code_actions) do |document|
        Requests::CodeActions.run(uri, document, range)
      end
    end

    def respond_with_document_highlight(uri, position)
      Requests::DocumentHighlight.run(store.get(uri), position)
    end

    def with_telemetry(request)
      result = nil
      error = nil

      request_time = Benchmark.realtime do
        result = yield
      rescue StandardError => e
        error = e
      end

      @writer.write(method: "telemetry/event", params: telemetry_params(request, request_time, error))
      result
    end

    def telemetry_params(request, request_time, error)
      uri = request.dig(:params, :textDocument, :uri)

      params = {
        request: request[:method],
        lspVersion: RubyLsp::VERSION,
        requestTime: request_time,
      }

      if error
        params[:errorClass] = error.class.name
        params[:errorMessage] = error.message
      end

      params[:uri] = uri if uri
      params
    end
  end
end
