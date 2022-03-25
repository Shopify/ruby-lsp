# frozen_string_literal: true

module RubyLsp
  module Requests
    class FoldingRanges < Visitor
      SIMPLE_FOLDABLES = [
        SyntaxTree::SClass,
        SyntaxTree::ClassDeclaration,
        SyntaxTree::ModuleDeclaration,
        SyntaxTree::DoBlock,
        SyntaxTree::BraceBlock,
        SyntaxTree::HashLiteral,
        SyntaxTree::If,
        SyntaxTree::Unless,
        SyntaxTree::Case,
        SyntaxTree::While,
        SyntaxTree::Until,
        SyntaxTree::For,
        SyntaxTree::Args,
        SyntaxTree::Heredoc,
      ].freeze

      def self.run(parsed_tree)
        new(parsed_tree).run
      end

      def initialize(parsed_tree)
        @parsed_tree = parsed_tree
        @ranges = []
        @partial_range = nil

        super()
      end

      def run
        visit(@parsed_tree.tree)
        emit_partial_range
        @ranges
      end

      private

      # For nodes that are simple to fold, we just re-use the same method body
      SIMPLE_FOLDABLES.each do |node_class|
        class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
          def visit_#{class_to_visit_method(node_class.name)}(node)
            add_simple_range(node)
            super
          end
        RUBY
      end

      def visit(node)
        super if handle_partial_range(node)
      end

      def visit_arg_paren(node)
        add_simple_range(node)
      end

      def visit_array_literal(node)
        add_simple_range(node)

        visit_all(node.contents.parts) if node.contents
      end

      def visit_begin(node)
        unless node.bodystmt.statements.empty?
          add_range(node.location.start_line - 1, node.bodystmt.statements.location.end_line - 1)
        end

        super
      end

      def visit_def(node)
        params_location = node.params.location

        if params_location.start_line < params_location.end_line
          add_range(params_location.end_line - 1, node.location.end_line - 1)
        else
          add_simple_range(node)
        end

        visit(node.bodystmt.statements)
      end
      alias_method :visit_defs, :visit_def

      def visit_statement_node(node)
        return if node.statements.empty?

        add_range(node.location.start_line - 1, node.statements.location.end_line - 1)
        visit_all(node.child_nodes)
      end
      alias_method :visit_else, :visit_statement_node
      alias_method :visit_elsif, :visit_statement_node
      alias_method :visit_when, :visit_statement_node
      alias_method :visit_ensure, :visit_statement_node
      alias_method :visit_rescue, :visit_statement_node

      def handle_partial_range(node)
        kind = case node
        when SyntaxTree::Comment
          "comment"
        when SyntaxTree::Command
          if node.message.value == "require" || node.message.value == "require_relative"
            "imports"
          end
        end

        if kind.nil?
          emit_partial_range
          return true
        end

        @partial_range = if @partial_range.nil?
          LanguageServer::Protocol::Interface::FoldingRange.new(
            start_line: node.location.start_line - 1,
            end_line: node.location.end_line - 1,
            kind: kind
          )
        elsif @partial_range.kind != kind
          emit_partial_range
          LanguageServer::Protocol::Interface::FoldingRange.new(
            start_line: node.location.start_line - 1,
            end_line: node.location.end_line - 1,
            kind: kind
          )
        else
          LanguageServer::Protocol::Interface::FoldingRange.new(
            start_line: @partial_range.start_line,
            end_line: node.location.end_line - 1,
            kind: @partial_range.kind
          )
        end

        false
      end

      def emit_partial_range
        return if @partial_range.nil?

        @ranges << @partial_range
        @partial_range = nil
      end

      def add_simple_range(node)
        location = node.location

        if location.start_line < location.end_line
          add_range(location.start_line - 1, location.end_line - 1)
        end
      end

      def add_range(start_line, end_line)
        @ranges << LanguageServer::Protocol::Interface::FoldingRange.new(
          start_line: start_line,
          end_line: end_line,
          kind: "region"
        )
      end
    end
  end
end
