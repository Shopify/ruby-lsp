# frozen_string_literal: true

require "language_server-protocol"

require_relative "handler"

module RubyLsp
  module Cli
    def self.start(_argv)
      handler = RubyLsp::Handler.new

      handler.config do
        on("initialize") do
          store.clear
          respond_with_capabilities
        end

        on("textDocument/didChange") do |request|
          uri = request.dig(:params, :textDocument, :uri)
          text = request.dig(:params, :contentChanges, 0, :text)
          store[uri] = text

          nil
        end

        on("textDocument/didOpen") do |request|
          uri = request.dig(:params, :textDocument, :uri)
          text = request.dig(:params, :textDocument, :text)
          store[uri] = text

          nil
        end

        on("textDocument/didClose") do |request|
          uri = request.dig(:params, :textDocument, :uri)
          store.delete(uri)

          nil
        end

        on("textDocument/foldingRange") do |request|
          respond_with_folding_ranges(request.dig(:params, :textDocument, :uri))
        end

        on("shutdown") { shutdown }
      end

      handler.start
    end
  end
end
