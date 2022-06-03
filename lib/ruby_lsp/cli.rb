# typed: strict
# frozen_string_literal: true

require "language_server-protocol"

require_relative "handler"

module RubyLsp
  module Cli
    extend T::Sig

    sig { void }
    def self.start
      handler = RubyLsp::Handler.new

      handler.config do
        on("initialize") do |request|
          store.clear
          initialization_options = request.dig(:params, :initializationOptions)

          respond_with_capabilities(initialization_options.fetch(:enabledFeatures, []))
        end

        on("textDocument/didChange") do |request|
          uri = request.dig(:params, :textDocument, :uri)
          store.push_edits(uri, request.dig(:params, :contentChanges))

          send_diagnostics(uri)
          RubyLsp::Handler::VOID
        end

        on("textDocument/didOpen") do |request|
          uri = request.dig(:params, :textDocument, :uri)
          text = request.dig(:params, :textDocument, :text)
          store.set(uri, text)

          send_diagnostics(uri)
          RubyLsp::Handler::VOID
        end

        on("textDocument/didClose") do |request|
          uri = request.dig(:params, :textDocument, :uri)
          store.delete(uri)

          RubyLsp::Handler::VOID
        end

        on("textDocument/documentSymbol") do |request|
          respond_with_document_symbol(request.dig(:params, :textDocument, :uri))
        end

        on("textDocument/foldingRange") do |request|
          respond_with_folding_ranges(request.dig(:params, :textDocument, :uri))
        end

        on("textDocument/selectionRange") do |request|
          respond_with_selection_ranges(
            request.dig(:params, :textDocument, :uri),
            request.dig(:params, :positions),
          )
        end

        on("textDocument/semanticTokens/full") do |request|
          respond_with_semantic_highlighting(request.dig(:params, :textDocument, :uri))
        end

        on("textDocument/formatting") do |request|
          respond_with_formatting(request.dig(:params, :textDocument, :uri))
        end

        on("textDocument/documentHighlight") do |request|
          respond_with_document_highlight(request.dig(:params, :textDocument, :uri), request.dig(:params, :position))
        end

        on("textDocument/codeAction") do |request|
          range = request.dig(:params, :range)
          start_line = range.dig(:start, :line)
          end_line = range.dig(:end, :line)
          respond_with_code_actions(request.dig(:params, :textDocument, :uri), (start_line..end_line))
        end

        on("shutdown") { shutdown }
      end

      handler.start
    end
  end
end
