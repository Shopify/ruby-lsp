# frozen_string_literal: true

require_relative "requests"
require_relative "store"

module Ruby
  module Lsp
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
            folding_range_provider: Interface::FoldingRangeClientCapabilities.new(
              line_folding_only: true
            )
          )
        )
      end

      def respond_with_folding_ranges(uri)
        Ruby::Lsp::Requests::FoldingRanges.run(store[uri])
      end
    end
  end
end
