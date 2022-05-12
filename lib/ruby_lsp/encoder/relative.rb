# frozen_string_literal: true

module RubyLsp
  module Encoder
    class Relative
      TOKEN_TYPES = [
        :variable,
        :method,
      ].freeze
      TOKEN_MODIFIERS = [].freeze

      def initialize(request)
        @tokens = request.run
        @delta = []
        @current_row = 0
        @current_column = 0
      end

      def run
        @tokens.each do |token|
          compute_delta(token) do |delta_line, delta_column|
            @delta.push(delta_line, delta_column, token.length, TOKEN_TYPES.index(token.classification), 0)
          end
        end

        LanguageServer::Protocol::Interface::SemanticTokens.new(data: @delta)
      end

      # The delta array is computed according to the LSP specification:
      # > The protocol for the token format relative uses relative
      # > positions, because most tokens remain stable relative to
      # > each other when edits are made in a file. This simplifies
      # > the computation of a delta if a server supports it. So each
      # > token is represented using 5 integers.

      # For more information on how each number is calculated, read:
      # https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_semanticTokens
      def compute_delta(token)
        row = token.location.start_line - 1
        column = token.location.start_column

        if row < @current_row
          raise InvalidTokenRowError, "Invalid token row detected: " \
            "Ensure tokens are added in the expected order."
        end

        delta_line = row - @current_row

        delta_column = column
        delta_column -= @current_column if delta_line == 0

        yield delta_line, delta_column

        @current_row = row
        @current_column = column
      end

      class InvalidTokenRowError < StandardError; end
    end
  end
end
