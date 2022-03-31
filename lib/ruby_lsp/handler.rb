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

    def respond_with_capabilities
      Interface::InitializeResult.new(
        capabilities: Interface::ServerCapabilities.new(
          text_document_sync: Interface::TextDocumentSyncOptions.new(
            change: Constant::TextDocumentSyncKind::FULL
          ),
          document_symbol_provider: Interface::DocumentSymbolClientCapabilities.new(
            hierarchical_document_symbol_support: true,
            symbol_kind: {
              value_set: Requests::DocumentSymbol::SYMBOL_KIND.values,
            }
          ),
          folding_range_provider: Interface::FoldingRangeClientCapabilities.new(
            line_folding_only: true
          ),
          semantic_tokens_provider: Interface::SemanticTokensRegistrationOptions.new(
            document_selector: { scheme: "file", language: "ruby" },
            legend: Interface::SemanticTokensLegend.new(
              token_types: Requests::SemanticHighlighting::TOKEN_TYPES,
              token_modifiers: Requests::SemanticHighlighting::TOKEN_MODIFIERS
            ),
            range: false,
            full: {
              delta: true,
            }
          ),
        )
      )
    end

    def respond_with_document_symbol(uri)
      RubyLsp::Requests::DocumentSymbol.run(store[uri])
    end

    def respond_with_folding_ranges(uri)
      Requests::FoldingRanges.run(store[uri])
    end

    def respond_with_semantic_highlighting(uri)
      Requests::SemanticHighlighting.run(store[uri])
    end
  end
end
