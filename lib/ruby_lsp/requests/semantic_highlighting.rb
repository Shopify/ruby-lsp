# frozen_string_literal: true

module RubyLsp
  module Requests
    class SemanticHighlighting < BaseRequest
      TOKEN_TYPES = [
        :variable,
        :method,
      ].freeze
      TOKEN_MODIFIERS = [].freeze

      def initialize(document)
        super

        @tokens = []
        @tree = document.tree
        @current_row = 0
        @current_column = 0
      end

      def run
        visit(@tree)
        LanguageServer::Protocol::Interface::SemanticTokens.new(data: @tokens)
      end

      def visit_m_assign(node)
        node.target.parts.each do |var_ref|
          add_token(var_ref.value.location, :variable)
        end
      end

      def visit_var_field(node)
        case node.value
        when SyntaxTree::Ident
          add_token(node.value.location, :variable)
        end
      end

      def visit_var_ref(node)
        case node.value
        when SyntaxTree::Ident
          add_token(node.value.location, :variable)
        end
      end

      def visit_a_ref_field(node)
        add_token(node.collection.value.location, :variable)
      end

      def visit_call(node)
        visit(node.receiver)
        add_token(node.message.location, :method)
        visit(node.arguments)
      end

      def visit_command(node)
        add_token(node.message.location, :method)
        visit(node.arguments)
      end

      def visit_command_call(node)
        visit(node.receiver)
        add_token(node.message.location, :method)
        visit(node.arguments)
      end

      def visit_fcall(node)
        add_token(node.value.location, :method)
        visit(node.arguments)
      end

      def visit_vcall(node)
        add_token(node.value.location, :method)
      end

      def add_token(location, classification)
        length = location.end_char - location.start_char

        compute_delta(location) do |delta_line, delta_column|
          @tokens.push(delta_line, delta_column, length, TOKEN_TYPES.index(classification), 0)
        end
      end

      # The delta array is computed according to the LSP specification:
      # > The protocol for the token format relative uses relative
      # > positions, because most tokens remain stable relative to
      # > each other when edits are made in a file. This simplifies
      # > the computation of a delta if a server supports it. So each
      # > token is represented using 5 integers.

      # For more information on how each number is calculated, read:
      # https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_semanticTokens
      def compute_delta(location)
        row = location.start_line - 1
        column = location.start_column

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
