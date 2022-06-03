# typed: true
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [folding ranges](https://microsoft.github.io/language-server-protocol/specification#textDocument_foldingRange)
    # request informs the editor of the ranges where code can be folded.
    #
    # # Example
    # ```ruby
    # def say_hello # <-- folding range start
    #   puts "Hello"
    # end # <-- folding range end
    # ```
    class FoldingRanges < BaseRequest
      SIMPLE_FOLDABLES = [
        SyntaxTree::ArrayLiteral,
        SyntaxTree::BraceBlock,
        SyntaxTree::Case,
        SyntaxTree::ClassDeclaration,
        SyntaxTree::Command,
        SyntaxTree::DoBlock,
        SyntaxTree::FCall,
        SyntaxTree::For,
        SyntaxTree::HashLiteral,
        SyntaxTree::Heredoc,
        SyntaxTree::If,
        SyntaxTree::ModuleDeclaration,
        SyntaxTree::SClass,
        SyntaxTree::Unless,
        SyntaxTree::Until,
        SyntaxTree::While,
      ].freeze

      NODES_WITH_STATEMENTS = [
        SyntaxTree::Else,
        SyntaxTree::Elsif,
        SyntaxTree::Ensure,
        SyntaxTree::In,
        SyntaxTree::Rescue,
        SyntaxTree::When,
      ].freeze

      def initialize(document)
        super

        @ranges = []
        @partial_range = nil
      end

      def run
        visit(@document.tree)
        emit_partial_range
        @ranges
      end

      private

      def visit(node)
        return unless handle_partial_range(node)

        case node
        when *SIMPLE_FOLDABLES
          add_node_range(node)
        when *NODES_WITH_STATEMENTS
          add_statements_range(node, node.statements)
        when SyntaxTree::Begin
          add_statements_range(node, node.bodystmt.statements)
        when SyntaxTree::Call, SyntaxTree::CommandCall
          add_call_range(node)
          return
        when SyntaxTree::Def, SyntaxTree::Defs
          add_def_range(node)
        when SyntaxTree::StringConcat
          add_string_concat(node)
          return
        end

        super
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
        when SyntaxTree::Comment
          "comment"
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

      def add_call_range(node)
        receiver = T.let(node.receiver, SyntaxTree::Node)
        loop do
          case receiver
          when SyntaxTree::Call
            visit(receiver.arguments)
            receiver = receiver.receiver
          when SyntaxTree::MethodAddBlock
            visit(receiver.block)
            receiver = receiver.call.receiver
          else
            break
          end
        end

        add_lines_range(receiver.location.start_line, node.location.end_line)

        visit(node.arguments)
      end

      def add_def_range(node)
        params_location = node.params.location

        if params_location.start_line < params_location.end_line
          add_lines_range(params_location.end_line, node.location.end_line)
        else
          add_node_range(node)
        end

        visit(node.bodystmt.statements)
      end

      def add_statements_range(node, statements)
        add_lines_range(node.location.start_line, statements.location.end_line) unless statements.empty?
      end

      def add_string_concat(node)
        left = T.let(node.left, SyntaxTree::Node)
        left = left.left while left.is_a?(SyntaxTree::StringConcat)

        add_lines_range(left.location.start_line, node.right.location.end_line)
      end

      def add_node_range(node)
        add_location_range(node.location)
      end

      def add_location_range(location)
        add_lines_range(location.start_line, location.end_line)
      end

      def add_lines_range(start_line, end_line)
        return if start_line >= end_line

        @ranges << LanguageServer::Protocol::Interface::FoldingRange.new(
          start_line: start_line - 1,
          end_line: end_line - 1,
          kind: "region"
        )
      end
    end
  end
end
