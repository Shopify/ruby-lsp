# typed: strict
# frozen_string_literal: true

# when SyntaxTree::CallNode
# when  SyntaxTree::CommandCall
# when SyntaxTree::Command
# when SyntaxTree::DefNode
# when SyntaxTree::StringConcat

module RubyLsp
  module Requests
    # ![Folding ranges demo](../../folding_ranges.gif)
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

    # TODO: explain why had to move this
    StatementNode = T.type_alias do
      T.any(
        SyntaxTree::Elsif,
        SyntaxTree::In,
        SyntaxTree::Rescue,
        SyntaxTree::When,
      )
    end
    class FoldingRanges < Listener
      extend T::Sig

      ResponseType = type_member { { fixed: T::Array[Interface::FoldingRange] } }

      sig { override.returns(ResponseType) }
      attr_reader :response

      SIMPLE_FOLDABLES = T.let(
        [
          SyntaxTree::ArrayLiteral,
          SyntaxTree::Begin,
          SyntaxTree::BlockNode,
          SyntaxTree::Case,
          SyntaxTree::ClassDeclaration,
          SyntaxTree::Else,
          SyntaxTree::Ensure,
          SyntaxTree::For,
          SyntaxTree::HashLiteral,
          SyntaxTree::Heredoc,
          SyntaxTree::IfNode,
          SyntaxTree::ModuleDeclaration,
          SyntaxTree::SClass,
          SyntaxTree::UnlessNode,
          SyntaxTree::UntilNode,
          SyntaxTree::WhileNode,
        ].freeze,
        T::Array[T.class_of(SyntaxTree::Node)],
      )

      NODES_WITH_STATEMENTS = T.let(
        [
          SyntaxTree::Elsif,
          SyntaxTree::In,
          SyntaxTree::Rescue,
          SyntaxTree::When,
        ].freeze,
        T::Array[T.class_of(SyntaxTree::Node)],
      )

      sig { params(emitter: EventEmitter, message_queue: Thread::Queue).void }
      def initialize(emitter, message_queue)
        super
        @response = T.let([], ResponseType)
        @partial_range = T.let(nil, T.nilable(PartialRange))

        emitter.register(
          self,
          :on_array_literal,
          :on_begin,
          :on_block_node,
          :on_case,
          :on_class_declaration,
          :on_else,
          :on_ensure,
          :on_for,
          :on_hash_literal,
          :on_heredoc,
          :on_if_node,
          :on_module_declaration,
          :on_sclass,
          :on_unless_node,
          :on_until_node,
          :on_while_node,
          :on_elsif,
          :on_in,
          :on_rescue,
          :on_when,
          :on_call_node,
          :on_command,
          :on_command_call,
          :on_def,
          :on_string_concat,
        )
      end

      # sig { override.returns(T.all(T::Array[Interface::FoldingRange], Object)) }
      # def run
      #   if @document.parsed?
      #     visit(@document.tree)
      #     emit_partial_range
      #   end
      #
      #   @ranges
      # end

      # private

      sig { params(node: T.nilable(SyntaxTree::Node)).void }
      def visit(node)
        return unless handle_partial_range(node)

        #
        # case node
        # when *SIMPLE_FOLDABLES
        #   location = T.must(node).location
        #   add_lines_range(location.start_line, location.end_line - 1)
        # when *NODES_WITH_STATEMENTS
        #   add_statements_range(T.must(node), T.cast(node, StatementNode).statements)
        # when SyntaxTree::CallNode, SyntaxTree::CommandCall
        #   # If there is a receiver, it may be a chained invocation,
        #   # so we need to process it in special way.
        #   if node.receiver.nil?
        #     location = node.location
        #     add_lines_range(location.start_line, location.end_line - 1)
        #   else
        #     add_call_range(node)
        #     return
        #   end
        # when SyntaxTree::Command
        #   unless same_lines_for_command_and_block?(node)
        #     location = node.location
        #     add_lines_range(location.start_line, location.end_line - 1)
        #   end
        # when SyntaxTree::DefNode
        #   add_def_range(node)
        # when SyntaxTree::StringConcat
        #   add_string_concat(node)
        #   return
        # end
        super
      end

      # TODO: proper types
      sig { params(node: T.untyped).void }
      def on_simple_foldable(node)
        return unless handle_partial_range(node)

        location = node.location
        add_lines_range(location.start_line, location.end_line - 1)
      end
      alias_method :on_array_literal, :on_simple_foldable
      alias_method :on_begin, :on_simple_foldable
      alias_method :on_block_node, :on_simple_foldable
      alias_method :on_case, :on_simple_foldable
      alias_method :on_class_declaration, :on_simple_foldable
      alias_method :on_else, :on_simple_foldable
      alias_method :on_ensure, :on_simple_foldable
      alias_method :on_for, :on_simple_foldable
      alias_method :on_hash_literal, :on_simple_foldable
      alias_method :on_heredoc, :on_simple_foldable
      alias_method :on_if_node, :on_simple_foldable
      alias_method :on_module_declaration, :on_simple_foldable
      alias_method :on_s_class, :on_simple_foldable
      alias_method :on_unless_node, :on_simple_foldable
      alias_method :on_until_node, :on_simple_foldable
      alias_method :on_while_node, :on_simple_foldable

      # TODO: proper types
      sig { params(node: T.untyped).void }
      def on_call(node)
        return unless handle_partial_range(node)

        # If there is a receiver, it may be a chained invocation,
        # so we need to process it in special way.
        if node.receiver.nil?
          location = node.location
          add_lines_range(location.start_line, location.end_line - 1)
        else
          add_call_range(node)
          # return ?
        end
      end
      alias_method :on_command_call, :on_call

      sig { params(node: StatementNode).void }
      def on_statement_node(node)
        return unless handle_partial_range(node)

        add_statements_range(node, node.statements)
      end
      alias_method :on_elsif, :on_statement_node
      alias_method :on_in, :on_statement_node
      alias_method :on_rescue, :on_statement_node
      alias_method :on_when, :on_statement_node

      sig { params(node: SyntaxTree::Command).void }
      def on_command(node)
        return unless handle_partial_range(node)

        unless same_lines_for_command_and_block?(node)
          location = node.location
          add_lines_range(location.start_line, location.end_line - 1)
        end
      end

      sig { params(node: SyntaxTree::StringConcat).void }
      def on_string_concat(node)
        return unless handle_partial_range(node)

        add_string_concat(node)
        # return ?
      end

      sig { params(node: SyntaxTree::DefNode).void }
      def on_def(node)
        return unless handle_partial_range(node)

        add_def_range(node)
      end

      # This is to prevent duplicate ranges
      sig { params(node: T.any(SyntaxTree::Command, SyntaxTree::CommandCall)).returns(T::Boolean) }
      def same_lines_for_command_and_block?(node)
        node_block = node.block
        return false unless node_block

        location = node.location
        block_location = node_block.location
        block_location.start_line == location.start_line && block_location.end_line == location.end_line
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

        sig { returns(Interface::FoldingRange) }
        def to_range
          Interface::FoldingRange.new(
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

        @response << @partial_range.to_range if @partial_range.multiline?
        @partial_range = nil
      end

      sig { params(node: T.any(SyntaxTree::CallNode, SyntaxTree::CommandCall)).void }
      def add_call_range(node)
        receiver = T.let(node.receiver, T.nilable(SyntaxTree::Node))

        loop do
          case receiver
          when SyntaxTree::CallNode
            visit(receiver.arguments)
            receiver = receiver.receiver
          when SyntaxTree::MethodAddBlock
            visit(receiver.block)
            receiver = receiver.call

            if receiver.is_a?(SyntaxTree::CallNode) || receiver.is_a?(SyntaxTree::CommandCall)
              receiver = receiver.receiver
            end
          else
            break
          end
        end

        if receiver
          unless node.is_a?(SyntaxTree::CommandCall) && same_lines_for_command_and_block?(node)
            add_lines_range(
              receiver.location.start_line,
              node.location.end_line - 1,
            )
          end
        end

        visit(node.arguments)
        visit(node.block) if node.is_a?(SyntaxTree::CommandCall)
      end

      sig { params(node: SyntaxTree::DefNode).void }
      def add_def_range(node)
        # For an endless method with no arguments, `node.params` returns `nil` for Ruby 3.0, but a `Syntax::Params`
        # for Ruby 3.1
        params = node.params
        return unless params

        params_location = params.location

        if params_location.start_line < params_location.end_line
          add_lines_range(params_location.end_line, node.location.end_line - 1)
        else
          location = node.location
          add_lines_range(location.start_line, location.end_line - 1)
        end

        bodystmt = node.bodystmt
        if bodystmt.is_a?(SyntaxTree::BodyStmt)
          visit(bodystmt.statements)
        else
          visit(bodystmt)
        end
      end

      sig { params(node: SyntaxTree::Node, statements: SyntaxTree::Statements).void }
      def add_statements_range(node, statements)
        return if statements.empty?

        add_lines_range(node.location.start_line, T.must(statements.body.last).location.end_line)
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

        @response << Interface::FoldingRange.new(
          start_line: start_line - 1,
          end_line: end_line - 1,
          kind: "region",
        )
      end
    end
  end
end
