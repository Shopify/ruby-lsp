# frozen_string_literal: true

require "language_server-protocol"

module Ruby
  module Lsp
    module Cli
      def self.start(_argv)
        writer = LanguageServer::Protocol::Transport::Stdio::Writer.new
        reader = LanguageServer::Protocol::Transport::Stdio::Reader.new

        subscribers = {
          initialize: -> {
            LanguageServer::Protocol::Interface::InitializeResult.new(
              capabilities: LanguageServer::Protocol::Interface::ServerCapabilities.new(
                text_document_sync: LanguageServer::Protocol::Interface::TextDocumentSyncOptions.new(
                  change: LanguageServer::Protocol::Constant::TextDocumentSyncKind::FULL
                ),
                completion_provider: LanguageServer::Protocol::Interface::CompletionOptions.new(
                  resolve_provider: true,
                  trigger_characters: %w(.)
                ),
                definition_provider: true
              )
            )
          }
        }

        reader.read do |request|
          result = subscribers[request[:method].to_sym].call
          writer.write(id: request[:id], result: result)
          exit
        end
      end
    end
  end
end
