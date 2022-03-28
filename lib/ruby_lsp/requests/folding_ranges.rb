# frozen_string_literal: true

module RubyLsp
  module Requests
    class FoldingRanges < Visitor
      SIMPLE_FOLDABLES = [
        SyntaxTree::Def,
        SyntaxTree::Defs,
        SyntaxTree::SClass,
        SyntaxTree::ClassDeclaration,
        SyntaxTree::ModuleDeclaration,
        SyntaxTree::DoBlock,
        SyntaxTree::BraceBlock,
        SyntaxTree::ArrayLiteral,
        SyntaxTree::HashLiteral,
        SyntaxTree::If,
        SyntaxTree::Unless,
        SyntaxTree::Case,
        SyntaxTree::While,
        SyntaxTree::Until,
        SyntaxTree::For,
        SyntaxTree::ArgParen,
        SyntaxTree::Heredoc,
      ].freeze

      def self.run(parsed_tree)
        new(parsed_tree).run
      end

      def initialize(parsed_tree)
        @parsed_tree = parsed_tree
        @ranges = []

        super()
      end

      def run
        visit(@parsed_tree.tree)
        @ranges
      end

      # For nodes that are simple to fold, we just re-use the same method body
      SIMPLE_FOLDABLES.each do |node_class|
        class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
          def visit_#{class_to_visit_method(node_class.name)}(node)
            add_simple_range(node)
            super
          end
        RUBY
      end

      def visit_else(node)
        add_statements_range(node)
        super
      end

      def visit_elsif(node)
        add_statements_range(node)
        super
      end

      def visit_when(node)
        add_statements_range(node)
        super
      end

      private

      def add_simple_range(node)
        location = node.location

        if location.start_line < location.end_line
          @ranges << LanguageServer::Protocol::Interface::FoldingRange.new(
            start_line: location.start_line - 1,
            end_line: location.end_line - 1,
            kind: "region"
          )
        end
      end

      def add_statements_range(node)
        unless node.statements.empty?
          @ranges << LanguageServer::Protocol::Interface::FoldingRange.new(
            start_line: node.location.start_line - 1,
            end_line: node.statements.location.end_line - 1,
            kind: "region"
          )
        end
      end
    end
  end
end
