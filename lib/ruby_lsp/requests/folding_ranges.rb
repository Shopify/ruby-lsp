# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Folding ranges demo](../../misc/folding_ranges.gif)
    #
    # The [folding ranges](https://microsoft.github.io/language-server-protocol/specification#textDocument_foldingRange)
    # request informs the editor of the ranges where and how code can be folded.
    #
    # # Example
    #
    # ```ruby
    # def say_hello # <-- folding range start
    #   puts "Hello"
    # end # <-- folding range end
    # ```
    class FoldingRanges < BaseRequest
      extend T::Sig

      SIMPLE_FOLDABLES = T.let([
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
        SyntaxTree::Else,
        SyntaxTree::Ensure,
        SyntaxTree::Begin,
      ].freeze, T::Array[T.class_of(SyntaxTree::Node)])

      NODES_WITH_STATEMENTS = T.let([
        SyntaxTree::Elsif,
        SyntaxTree::In,
        SyntaxTree::Rescue,
        SyntaxTree::When,
      ].freeze, T::Array[T.class_of(SyntaxTree::Node)])

      StatementNode = T.type_alias do
        T.any(
          SyntaxTree::Elsif,
          SyntaxTree::In,
          SyntaxTree::Rescue,
          SyntaxTree::When,
        )
      end

      sig { params(document: Document).void }
      def initialize(document)
        super

        @ranges = T.let([], T::Array[LanguageServer::Protocol::Interface::FoldingRange])
        @partial_range = T.let(nil, T.nilable(PartialRange))
      end

      sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Interface::FoldingRange], Object)) }
      def run
        if @document.parsed?
          visit(@document.tree)
          emit_partial_range
        end

        @ranges
      end

      private

      sig { override.params(node: T.nilable(SyntaxTree::Node)).void }
      def visit(node)
        return unless handle_partial_range(node)

        case node
        when *SIMPLE_FOLDABLES
          location = T.must(node).location
          add_lines_range(location.start_line, location.end_line - 1)
        when *NODES_WITH_STATEMENTS
          add_statements_range(T.must(node), T.cast(node, StatementNode).statements)
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
        extend T::Sig

        sig { returns(String) }
        attr_reader :kind

        sig { returns(Integer) }
        attr_reader :end_line

        class << self
          extend T::Sig

          sig { params(node: SyntaxTree::Node, kind: String).returns(PartialRange) }
          def from(node, kind)
            new(node.location.start_line - 1, node.location.end_line - 1, kind)
          end
        end

        sig { params(start_line: Integer, end_line: Integer, kind: String).void }
        def initialize(start_line, end_line, kind)
          @start_line = start_line
          @end_line = end_line
          @kind = kind
        end

        sig { params(node: SyntaxTree::Node).returns(PartialRange) }
        def extend_to(node)
          @end_line = node.location.end_line - 1
          self
        end

        sig { params(node: SyntaxTree::Node).returns(T::Boolean) }
        def new_section?(node)
          node.is_a?(SyntaxTree::Comment) && @end_line + 1 != node.location.start_line - 1
        end

        sig { returns(LanguageServer::Protocol::Interface::FoldingRange) }
        def to_range
          LanguageServer::Protocol::Interface::FoldingRange.new(
            start_line: @start_line,
            end_line: @end_line,
            kind: @kind,
          )
        end

        sig { returns(T::Boolean) }
        def multiline?
          @end_line > @start_line
        end
      end

      sig { params(node: T.nilable(SyntaxTree::Node)).returns(T::Boolean) }
      def handle_partial_range(node)
        kind = partial_range_kind(node)

        if kind.nil?
          emit_partial_range
          return true
        end

        target_node = T.must(node)
        @partial_range = if @partial_range.nil?
          PartialRange.from(target_node, kind)
        elsif @partial_range.kind != kind || @partial_range.new_section?(target_node)
          emit_partial_range
          PartialRange.from(target_node, kind)
        else
          @partial_range.extend_to(target_node)
        end

        false
      end

      sig { params(node: T.nilable(SyntaxTree::Node)).returns(T.nilable(String)) }
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

      sig { void }
      def emit_partial_range
        return if @partial_range.nil?

        @ranges << @partial_range.to_range if @partial_range.multiline?
        @partial_range = nil
      end

      sig { params(node: T.any(SyntaxTree::Call, SyntaxTree::CommandCall)).void }
      def add_call_range(node)
        receiver = T.let(node.receiver, SyntaxTree::Node)
        loop do
          case receiver
          when SyntaxTree::Call
            visit(receiver.arguments)
            receiver = receiver.receiver
          when SyntaxTree::MethodAddBlock
            visit(receiver.block)
            receiver = receiver.call

            if receiver.is_a?(SyntaxTree::Call) || receiver.is_a?(SyntaxTree::CommandCall)
              receiver = receiver.receiver
            end
          else
            break
          end
        end

        add_lines_range(receiver.location.start_line, node.location.end_line - 1)

        visit(node.arguments)
      end

      sig { params(node: T.any(SyntaxTree::Def, SyntaxTree::Defs)).void }
      def add_def_range(node)
        params_location = node.params.location

        if params_location.start_line < params_location.end_line
          add_lines_range(params_location.end_line, node.location.end_line - 1)
        else
          location = node.location
          add_lines_range(location.start_line, location.end_line - 1)
        end

        visit(node.bodystmt.statements)
      end

      sig { params(node: SyntaxTree::Node, statements: SyntaxTree::Statements).void }
      def add_statements_range(node, statements)
        add_lines_range(node.location.start_line, statements.body.last.location.end_line) unless statements.empty?
      end

      sig { params(node: SyntaxTree::StringConcat).void }
      def add_string_concat(node)
        left = T.let(node.left, SyntaxTree::Node)
        left = left.left while left.is_a?(SyntaxTree::StringConcat)

        add_lines_range(left.location.start_line, node.right.location.end_line - 1)
      end

      sig { params(start_line: Integer, end_line: Integer).void }
      def add_lines_range(start_line, end_line)
        return if start_line >= end_line

        @ranges << LanguageServer::Protocol::Interface::FoldingRange.new(
          start_line: start_line - 1,
          end_line: end_line - 1,
          kind: "region",
        )
      end
    end
  end
end
