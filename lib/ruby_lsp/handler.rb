# frozen_string_literal: true

require "ruby_lsp/requests"
require "ruby_lsp/store"

module RubyLsp
  class Handler
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
        handle(request)
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
      result = @handlers[request[:method]]&.call(request)
      @writer.write(id: request[:id], result: result) if result
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
          document_symbol_provider: document_symbol_provider,
          folding_range_provider: folding_ranges_provider,
          semantic_tokens_provider: semantic_tokens_provider,
          document_formatting_provider: enabled_features.include?("formatting"),
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

    def respond_with_semantic_highlighting(uri)
      store.cache_fetch(uri, :semantic_highlighting) do |document|
        Requests::SemanticHighlighting.run(document)
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
  end
end
