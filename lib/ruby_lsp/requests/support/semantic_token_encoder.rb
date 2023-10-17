# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class SemanticTokenEncoder
        extend T::Sig

        sig { void }
        def initialize
          @current_row = T.let(0, Integer)
          @current_column = T.let(0, Integer)
        end

        sig do
          params(
            tokens: T::Array[SemanticHighlighting::SemanticToken],
          ).returns(Interface::SemanticTokens)
        end
        def encode(tokens)
          delta = tokens
            .sort_by do |token|
              [token.location.start_line, token.location.start_column]
            end
            .flat_map do |token|
              compute_delta(token)
            end

          Interface::SemanticTokens.new(data: delta)
        end

        # The delta array is computed according to the LSP specification:
        # > The protocol for the token format relative uses relative
        # > positions, because most tokens remain stable relative to
        # > each other when edits are made in a file. This simplifies
        # > the computation of a delta if a server supports it. So each
        # > token is represented using 5 integers.

        # For more information on how each number is calculated, read:
        # https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_semanticTokens
        sig { params(token: SemanticHighlighting::SemanticToken).returns(T::Array[Integer]) }
        def compute_delta(token)
          row = token.location.start_line - 1
          column = token.location.start_column

          begin
            delta_line = row - @current_row

            delta_column = column
            delta_column -= @current_column if delta_line == 0

            [delta_line, delta_column, token.length, token.type, encode_modifiers(token.modifier)]
          ensure
            @current_row = row
            @current_column = column
          end
        end

        # Encode an array of modifiers to positions onto a bit flag
        # For example, [:default_library] will be encoded as
        # 0b1000000000, as :default_library is the 10th bit according
        # to the token modifiers index map.
        sig { params(modifiers: T::Array[Integer]).returns(Integer) }
        def encode_modifiers(modifiers)
          modifiers.inject(0) do |encoded_modifiers, modifier|
            encoded_modifiers | (1 << modifier)
          end
        end
      end
    end
  end
end
