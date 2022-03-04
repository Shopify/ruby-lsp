# frozen_string_literal: true

module Ruby
  module Lsp
    class Handler
      attr_reader :writer, :reader, :handlers

      Interface = LanguageServer::Protocol::Interface
      Constant = LanguageServer::Protocol::Constant
      Transport = LanguageServer::Protocol::Transport

      def initialize
        @writer = Transport::Stdio::Writer.new
        @reader = Transport::Stdio::Reader.new
        @handlers = {}
      end

      def start
        puts "Starting server..."
        reader.read do |request|
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
        result = subscribers[request[:method].to_sym].call
        writer.write(request[:id], result)
      end

      def respond_with_capabilities
        Interface::InitializeResult.new(
          capabilities: Interface::ServerCapabilities.new(
            text_document_sync: Interface::TextDocumentSyncOptions.new(
              change: Constant::TextDocumentSyncKind::FULL
            ),
            completion_provider: Interface::CompletionOptions.new(
              resolve_provider: true,
              trigger_characters: ["."]
            ),
            definition_provider: true
          )
        )
      end
    end
  end
end
