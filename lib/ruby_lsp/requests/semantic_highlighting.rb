# frozen_string_literal: true

module RubyLsp
  module Requests
    class SemanticHighlighting < Visitor
      TOKEN_TYPES = [
        :local_variable,
        :method_call,
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

      def visit_assign(node)
        case node.target
        when SyntaxTree::ARefField
          add_token(node.target.collection.value.location, :local_variable)
        else
          add_token(node.target.value.location, :local_variable)
        end
      end

      def visit_m_assign(node)
        node.target.parts.each do |var_ref|
          add_token(var_ref.value.location, :local_variable)
        end
      end

      def visit_var_field(node)
        add_token(node.value.location, :local_variable)
      end

      def visit_var_ref(node)
        add_token(node.value.location, :local_variable)
      end

      def visit_call(node)
        super
        add_token(node.message.location, :method_call)
      end

      def visit_command(node)
        add_token(node.message.location, :method_call)
      end

      def visit_f_call(node)
        add_token(node.value.location, :method_call)
      end

      def visit_v_call(node)
        add_token(node.value.location, :method_call)
      end

      private

      def add_token(location, classification)
        length = location.end_char - location.start_char
        row = location.start_line - 1

        line = @parser.line_counts[location.start_line - 1]
        column = location.start_char - line.start

        delta_line = row - @current_row
        delta_column = @current_row == row ? column - @current_column : column

        @tokens.push(delta_line, delta_column, length, TOKEN_TYPES.index(classification), 0)
        @current_row = row
        @current_column = column
      end
    end
  end
end
