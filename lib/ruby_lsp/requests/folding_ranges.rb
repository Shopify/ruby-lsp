# frozen_string_literal: true

module RubyLsp
  module Requests
    class FoldingRanges < Visitor
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
        @ranges.filter! { |range| range.end_line > range.start_line } || @ranges
      end

      private

      def visit(node)
        return unless node

        case node
        when SyntaxTree::ArgParen,
             SyntaxTree::ArrayLiteral,
             SyntaxTree::BraceBlock,
             SyntaxTree::Case,
             SyntaxTree::ClassDeclaration,
             SyntaxTree::DoBlock,
             SyntaxTree::For,
             SyntaxTree::HashLiteral,
             SyntaxTree::Heredoc,
             SyntaxTree::If,
             SyntaxTree::ModuleDeclaration,
             SyntaxTree::SClass,
             SyntaxTree::Unless,
             SyntaxTree::Until,
             SyntaxTree::While
          add_node_range(node)
          visit_all(node.child_nodes)
        when SyntaxTree::Call,
             SyntaxTree::FCall,
             SyntaxTree::StringConcat
          add_node_range(node)
        when SyntaxTree::Begin
          add_statements_range(node, node.bodystmt.statements)
          visit_all(node.child_nodes)
        when SyntaxTree::Else,
             SyntaxTree::Elsif,
             SyntaxTree::Ensure,
             SyntaxTree::Rescue,
             SyntaxTree::When
          add_statements_range(node, node.statements)
          visit_all(node.child_nodes)
        when SyntaxTree::Def, SyntaxTree::Defs
          add_def_range(node)
          visit(node.bodystmt)
        when SyntaxTree::Command
          add_import_range(node)
        when SyntaxTree::Comment
          add_comment_range(node)
        else
          visit_all(node.child_nodes)
        end
      end

      def add_statements_range(node, statements)
        return if statements.empty?

        add_lines_range(node.location.start_line, statements.location.end_line)
      end

      def add_def_range(node)
        params_location = node.params.location

        if params_location.start_line < params_location.end_line
          add_lines_range(params_location.end_line, node.location.end_line)
        else
          add_node_range(node)
        end
      end

      def add_comment_range(node)
        last_range = @ranges.last
        if last_range&.kind == "comment" && last_range&.end_line == node.location.start_line - 2
          extend_last_range_to_location(node.location)
        else
          add_node_range(node, kind: "comment")
        end
      end

      def add_import_range(node)
        if node.message.value != "require" && node.message.value != "require_relative"
          add_node_range(node)
          return
        end

        last_range = @ranges.last
        if last_range&.kind == "imports"
          extend_last_range_to_location(node.location)
        else
          add_node_range(node, kind: "imports")
        end
      end

      def add_node_range(node, kind: "region")
        add_location_range(node.location, kind: kind)
      end

      def add_location_range(location, kind: "region")
        add_lines_range(location.start_line, location.end_line, kind: kind)
      end

      def add_lines_range(start_line, end_line, kind: "region")
        @ranges << LanguageServer::Protocol::Interface::FoldingRange.new(
          start_line: start_line - 1,
          end_line: end_line - 1,
          kind: kind
        )
      end

      def extend_last_range_to_location(location)
        return if @ranges.empty?

        last_range = @ranges.last
        @ranges[-1] = LanguageServer::Protocol::Interface::FoldingRange.new(
          start_line: last_range.start_line,
          end_line: location.end_line - 1,
          kind: last_range.kind
        )
      end
    end
  end
end
