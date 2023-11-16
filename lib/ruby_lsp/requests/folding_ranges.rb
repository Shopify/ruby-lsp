# typed: strict
# frozen_string_literal: true

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
    class FoldingRanges < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T::Array[Interface::FoldingRange] } }

      sig { params(comments: T::Array[Prism::Comment], dispatcher: Prism::Dispatcher, queue: Thread::Queue).void }
      def initialize(comments, dispatcher, queue)
        super(dispatcher, queue)

        @_response = T.let([], ResponseType)
        @requires = T.let([], T::Array[Prism::CallNode])
        @finalized_response = T.let(false, T::Boolean)
        @comments = comments

        dispatcher.register(
          self,
          :on_if_node_enter,
          :on_in_node_enter,
          :on_rescue_node_enter,
          :on_when_node_enter,
          :on_interpolated_string_node_enter,
          :on_array_node_enter,
          :on_block_node_enter,
          :on_case_node_enter,
          :on_class_node_enter,
          :on_module_node_enter,
          :on_for_node_enter,
          :on_hash_node_enter,
          :on_singleton_class_node_enter,
          :on_unless_node_enter,
          :on_until_node_enter,
          :on_while_node_enter,
          :on_else_node_enter,
          :on_ensure_node_enter,
          :on_begin_node_enter,
          :on_string_concat_node_enter,
          :on_def_node_enter,
          :on_call_node_enter,
          :on_lambda_node_enter,
        )
      end

      sig { override.returns(ResponseType) }
      def _response
        unless @finalized_response
          push_comment_ranges
          emit_requires_range
          @finalized_response = true
        end

        @_response
      end

      sig { params(node: Prism::IfNode).void }
      def on_if_node_enter(node)
        add_statements_range(node)
      end

      sig { params(node: Prism::InNode).void }
      def on_in_node_enter(node)
        add_statements_range(node)
      end

      sig { params(node: Prism::RescueNode).void }
      def on_rescue_node_enter(node)
        add_statements_range(node)
      end

      sig { params(node: Prism::WhenNode).void }
      def on_when_node_enter(node)
        add_statements_range(node)
      end

      sig { params(node: Prism::InterpolatedStringNode).void }
      def on_interpolated_string_node_enter(node)
        opening_loc = node.opening_loc
        closing_loc = node.closing_loc

        add_lines_range(opening_loc.start_line, closing_loc.start_line - 1) if opening_loc && closing_loc
      end

      sig { params(node: Prism::ArrayNode).void }
      def on_array_node_enter(node)
        add_simple_range(node)
      end

      sig { params(node: Prism::BlockNode).void }
      def on_block_node_enter(node)
        add_simple_range(node)
      end

      sig { params(node: Prism::CaseNode).void }
      def on_case_node_enter(node)
        add_simple_range(node)
      end

      sig { params(node: Prism::ClassNode).void }
      def on_class_node_enter(node)
        add_simple_range(node)
      end

      sig { params(node: Prism::ModuleNode).void }
      def on_module_node_enter(node)
        add_simple_range(node)
      end

      sig { params(node: Prism::ForNode).void }
      def on_for_node_enter(node)
        add_simple_range(node)
      end

      sig { params(node: Prism::HashNode).void }
      def on_hash_node_enter(node)
        add_simple_range(node)
      end

      sig { params(node: Prism::SingletonClassNode).void }
      def on_singleton_class_node_enter(node)
        add_simple_range(node)
      end

      sig { params(node: Prism::UnlessNode).void }
      def on_unless_node_enter(node)
        add_simple_range(node)
      end

      sig { params(node: Prism::UntilNode).void }
      def on_until_node_enter(node)
        add_simple_range(node)
      end

      sig { params(node: Prism::WhileNode).void }
      def on_while_node_enter(node)
        add_simple_range(node)
      end

      sig { params(node: Prism::ElseNode).void }
      def on_else_node_enter(node)
        add_simple_range(node)
      end

      sig { params(node: Prism::EnsureNode).void }
      def on_ensure_node_enter(node)
        add_simple_range(node)
      end

      sig { params(node: Prism::BeginNode).void }
      def on_begin_node_enter(node)
        add_simple_range(node)
      end

      sig { params(node: Prism::StringConcatNode).void }
      def on_string_concat_node_enter(node)
        left = T.let(node.left, Prism::Node)
        left = left.left while left.is_a?(Prism::StringConcatNode)

        add_lines_range(left.location.start_line, node.right.location.end_line - 1)
      end

      sig { params(node: Prism::DefNode).void }
      def on_def_node_enter(node)
        params = node.parameters
        parameter_loc = params&.location
        location = node.location

        if params && parameter_loc.end_line > location.start_line
          # Multiline parameters
          add_lines_range(location.start_line, parameter_loc.end_line)
          add_lines_range(parameter_loc.end_line + 1, location.end_line - 1)
        else
          add_lines_range(location.start_line, location.end_line - 1)
        end
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_enter(node)
        # If we find a require, don't visit the child nodes (prevent `super`), so that we can keep accumulating into
        # the `@requires` array and then push the range whenever we find a node that isn't a CallNode
        if require?(node)
          @requires << node
          return
        end

        location = node.location
        add_lines_range(location.start_line, location.end_line - 1)
      end

      sig { params(node: Prism::LambdaNode).void }
      def on_lambda_node_enter(node)
        add_simple_range(node)
      end

      private

      sig { void }
      def push_comment_ranges
        # Group comments that are on consecutive lines and then push ranges for each group that has at least 2 comments
        @comments.chunk_while do |this, other|
          this.location.end_line + 1 == other.location.start_line
        end.each do |chunk|
          next if chunk.length == 1

          @_response << Interface::FoldingRange.new(
            start_line: T.must(chunk.first).location.start_line - 1,
            end_line: T.must(chunk.last).location.end_line - 1,
            kind: "comment",
          )
        end
      end

      sig { void }
      def emit_requires_range
        if @requires.length > 1
          @_response << Interface::FoldingRange.new(
            start_line: T.must(@requires.first).location.start_line - 1,
            end_line: T.must(@requires.last).location.end_line - 1,
            kind: "imports",
          )
        end

        @requires.clear
      end

      sig { params(node: Prism::CallNode).returns(T::Boolean) }
      def require?(node)
        message = node.message
        return false unless message == "require" || message == "require_relative"

        receiver = node.receiver
        return false unless receiver.nil? || receiver.slice == "Kernel"

        arguments = node.arguments&.arguments
        return false unless arguments

        arguments.length == 1 && arguments.first.is_a?(Prism::StringNode)
      end

      sig { params(node: T.any(Prism::IfNode, Prism::InNode, Prism::RescueNode, Prism::WhenNode)).void }
      def add_statements_range(node)
        statements = node.statements
        return unless statements

        body = statements.body
        return if body.empty?

        add_lines_range(node.location.start_line, T.must(body.last).location.end_line)
      end

      sig { params(node: Prism::Node).void }
      def add_simple_range(node)
        location = node.location
        add_lines_range(location.start_line, location.end_line - 1)
      end

      sig { params(start_line: Integer, end_line: Integer).void }
      def add_lines_range(start_line, end_line)
        emit_requires_range
        return if start_line >= end_line

        @_response << Interface::FoldingRange.new(
          start_line: start_line - 1,
          end_line: end_line - 1,
          kind: "region",
        )
      end
    end
  end
end
