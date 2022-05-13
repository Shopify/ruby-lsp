# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class SemanticTokenEncoder
        def initialize
          @current_row = 0
          @current_column = 0
        end

        def encode(tokens)
          tokens = sort(tokens)

          delta = tokens.flat_map do |token|
            compute_delta(token)
          end

          LanguageServer::Protocol::Interface::SemanticTokens.new(data: delta)
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
          delta_line = row - @current_row

          delta_column = column
          delta_column -= @current_column if delta_line == 0

          [delta_line, delta_column, token.length, token.type, token.modifier]
        ensure
          @current_row = row
          @current_column = column
        end

        def sort(tokens)
          tokens.sort_by { |token| token.location.start_column }
            .sort_by { |token| token.location.start_line }
        end
      end
    end
  end
end
