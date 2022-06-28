# typed: strict
# frozen_string_literal: true

require "ruby_lsp/requests"
require "ruby_lsp/store"
require "benchmark"

module RubyLsp
  class Handler
    extend T::Sig
    VOID = T.let(Object.new.freeze, Object)

    sig { returns(Store) }
    attr_reader :store

    Interface = LanguageServer::Protocol::Interface
    Constant = LanguageServer::Protocol::Constant
    Transport = LanguageServer::Protocol::Transport

    sig { void }
    def initialize
      @writer = T.let(Transport::Stdio::Writer.new, Transport::Stdio::Writer)
      @reader = T.let(Transport::Stdio::Reader.new, Transport::Stdio::Reader)
      @handlers = T.let({}, T::Hash[String, T.proc.params(request: T::Hash[Symbol, T.untyped]).returns(T.untyped)])
      @store = T.let(Store.new, Store)
    end

    sig { void }
    def start
      $stderr.puts "Starting Ruby LSP..."
      @reader.read { |request| handle(request) }
    end

    sig { params(blk: T.proc.bind(Handler).params(arg0: T.untyped).void).void }
    def config(&blk)
      instance_exec(&blk)
    end

    private

    sig do
      params(
        msg: String,
        blk: T.proc.bind(Handler).params(request: T::Hash[Symbol, T.untyped]).returns(T.untyped)
      ).void
    end
    def on(msg, &blk)
      @handlers[msg] = blk
    end

    sig { params(request: T::Hash[Symbol, T.untyped]).void }
    def handle(request)
      result = T.let(nil, T.untyped)
      error = T.let(nil, T.nilable(StandardError))
      handler = @handlers[request[:method]]

      request_time = Benchmark.realtime do
        if handler
          begin
            result = handler.call(request)
          rescue StandardError => e
            error = e
          end

          if error
            @writer.write(
              {
                id: request[:id],
                error: { code: Constant::ErrorCodes::INTERNAL_ERROR, message: error.inspect, data: request.to_json },
              }
            )
          elsif result != VOID
            @writer.write(id: request[:id], result: result)
          end
        end
      end

      @writer.write(method: "telemetry/event", params: telemetry_params(request, request_time, error))
    end

    sig { void }
    def shutdown
      $stderr.puts "Shutting down Ruby LSP..."
      store.clear
    end

    sig { params(enabled_features: T::Array[String]).returns(Interface::InitializeResult) }
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
            token_modifiers: Requests::SemanticHighlighting::TOKEN_MODIFIERS.keys
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

    sig { params(uri: String).returns(T::Array[LanguageServer::Protocol::Interface::DocumentSymbol]) }
    def respond_with_document_symbol(uri)
      store.cache_fetch(uri, :document_symbol) do |document|
        RubyLsp::Requests::DocumentSymbol.new(document).run
      end
    end

    sig { params(uri: String).returns(T::Array[LanguageServer::Protocol::Interface::FoldingRange]) }
    def respond_with_folding_ranges(uri)
      store.cache_fetch(uri, :folding_ranges) do |document|
        Requests::FoldingRanges.new(document).run
      end
    end

    sig do
      params(
        uri: String,
        positions: T::Array[Document::PositionShape]
      ).returns(T::Array[T.nilable(RubyLsp::Requests::Support::SelectionRange)])
    end
    def respond_with_selection_ranges(uri, positions)
      ranges = store.cache_fetch(uri, :selection_ranges) do |document|
        Requests::SelectionRanges.new(document).run
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

    sig { params(uri: String).returns(LanguageServer::Protocol::Interface::SemanticTokens) }
    def respond_with_semantic_highlighting(uri)
      store.cache_fetch(uri, :semantic_highlighting) do |document|
        T.cast(
          Requests::SemanticHighlighting.new(document, encoder: Requests::Support::SemanticTokenEncoder.new).run,
          LanguageServer::Protocol::Interface::SemanticTokens
        )
      end
    end

    sig { params(uri: String).returns(T.nilable(T::Array[LanguageServer::Protocol::Interface::TextEdit])) }
    def respond_with_formatting(uri)
      Requests::Formatting.new(uri, store.get(uri)).run
    end

    sig { params(uri: String).void }
    def send_diagnostics(uri)
      response = store.cache_fetch(uri, :diagnostics) do |document|
        Requests::Diagnostics.new(uri, document).run
      end

      @writer.write(
        method: "textDocument/publishDiagnostics",
        params: Interface::PublishDiagnosticsParams.new(
          uri: uri,
          diagnostics: response.map(&:to_lsp_diagnostic)
        )
      )
    end

    sig { params(uri: String).void }
    def clear_diagnostics(uri)
      @writer.write(
        method: "textDocument/publishDiagnostics",
        params: Interface::PublishDiagnosticsParams.new(uri: uri, diagnostics: [])
      )
    end

    sig do
      params(uri: String, range: T::Range[Integer]).returns(T::Array[LanguageServer::Protocol::Interface::CodeAction])
    end
    def respond_with_code_actions(uri, range)
      store.cache_fetch(uri, :code_actions) do |document|
        Requests::CodeActions.new(uri, document, range).run
      end
    end

    sig do
      params(
        uri: String,
        position: Document::PositionShape
      ).returns(T::Array[LanguageServer::Protocol::Interface::DocumentHighlight])
    end
    def respond_with_document_highlight(uri, position)
      Requests::DocumentHighlight.new(store.get(uri), position).run
    end

    sig do
      params(
        request: T::Hash[Symbol, T.untyped],
        request_time: Float,
        error: T.nilable(StandardError)
      ).returns(T::Hash[Symbol, T.any(String, Float)])
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

      params[:uri] = uri.sub(%r{.*://#{Dir.home}}, "~") if uri
      params
    end
  end
end
