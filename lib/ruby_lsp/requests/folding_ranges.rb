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
        emit_partial_range
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
          add_node_range(node)
          visit_all(node.child_nodes) if handle_partial_range(node)
        when SyntaxTree::Comment
          add_comment_range(node)
        else
          super if handle_partial_range(node)
        end
      end

      class PartialRange
        attr_reader :kind, :end_line

        def self.from(node, kind)
          new(node.location.start_line - 1, node.location.end_line - 1, kind)
        end

        def initialize(start_line, end_line, kind)
          @start_line = start_line
          @end_line = end_line
          @kind = kind
        end

        def extend_to(node)
          @end_line = node.location.end_line - 1
          self
        end

        def new_section?(node)
          node.is_a?(SyntaxTree::Comment) && @end_line + 1 != node.location.start_line - 1
        end

        def to_range
          LanguageServer::Protocol::Interface::FoldingRange.new(
            start_line: @start_line,
            end_line: @end_line,
            kind: @kind
          )
        end
      end

      def handle_partial_range(node)
        kind = partial_range_kind(node)

        if kind.nil?
          emit_partial_range
          return true
        end

        @partial_range = if @partial_range.nil?
          PartialRange.from(node, kind)
        elsif @partial_range.kind != kind || @partial_range.new_section?(node)
          emit_partial_range
          PartialRange.from(node, kind)
        else
          @partial_range.extend_to(node)
        end

        false
      end

      def partial_range_kind(node)
        case node
        when SyntaxTree::Command
          if node.message.value == "require" || node.message.value == "require_relative"
            "imports"
          end
        end
      end

      def emit_partial_range
        return if @partial_range.nil?

        @ranges << @partial_range.to_range
        @partial_range = nil
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
