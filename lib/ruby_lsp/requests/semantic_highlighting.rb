# frozen_string_literal: true

module RubyLsp
  module Requests
    class SemanticHighlighting < Visitor
      TOKEN_TYPES = [
        :local_variable,
        :method_call,
        :instance_variable,
      ].freeze
      TOKEN_MODIFIERS = [].freeze

      def self.run(parsed_tree)
        new(parsed_tree).run
      end

      def initialize(parsed_tree)
        @tokens = []
        @parser = parsed_tree.parser
        @tree = parsed_tree.tree
        @current_row = 0
        @current_column = 0

        super()
      end

      def run
        visit(@tree)
        LanguageServer::Protocol::Interface::SemanticTokens.new(data: @tokens)
      end

      private

      def visit_assign(node)
        super
      end

      def visit_m_assign(node)
        node.target.parts.each do |var_ref|
          add_token(var_ref.value.location, :local_variable)
        end
      end

      def visit_var_field(node)
        case node.value
        when SyntaxTree::Ident
          add_token(node.value.location, :local_variable)
        when SyntaxTree::IVar
          add_token(node.value.location, :instance_variable)
        end
      end

      def visit_var_ref(node)
        case node.value
        when SyntaxTree::Ident
          add_token(node.value.location, :local_variable)
        when SyntaxTree::IVar
          add_token(node.value.location, :instance_variable)
        end
      end

      def visit_a_ref_field(node)
        add_token(node.collection.value.location, :local_variable)
      end

      def visit_call(node)
        visit(node.receiver)
        add_token(node.message.location, :method_call)
        visit(node.arguments)
      end

      def visit_command(node)
        add_token(node.message.location, :method_call)
        visit(node.arguments)
      end

      def visit_command_call(node)
        visit(node.receiver)
        add_token(node.message.location, :method_call)
        visit(node.arguments)
      end

      def visit_f_call(node)
        add_token(node.value.location, :method_call)
        visit(node.arguments)
      end

      def visit_v_call(node)
        add_token(node.value.location, :method_call)
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

        line = @parser.line_counts[location.start_line - 1]
        column = location.start_char - line.start

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
