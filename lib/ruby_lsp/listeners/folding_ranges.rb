# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class FoldingRanges
      include Requests::Support::Common

      #: (ResponseBuilders::CollectionResponseBuilder[Interface::FoldingRange] response_builder, Array[Prism::Comment] comments, Prism::Dispatcher dispatcher) -> void
      def initialize(response_builder, comments, dispatcher)
        @response_builder = response_builder
        @requires = [] #: Array[Prism::CallNode]
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
          :on_case_match_node_enter,
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
          :on_def_node_enter,
          :on_call_node_enter,
          :on_lambda_node_enter,
        )
      end

      #: -> void
      def finalize_response!
        push_comment_ranges
        emit_requires_range
      end

      #: (Prism::IfNode node) -> void
      def on_if_node_enter(node)
        add_statements_range(node)
      end

      #: (Prism::InNode node) -> void
      def on_in_node_enter(node)
        add_statements_range(node)
      end

      #: (Prism::RescueNode node) -> void
      def on_rescue_node_enter(node)
        add_statements_range(node)
      end

      #: (Prism::WhenNode node) -> void
      def on_when_node_enter(node)
        add_statements_range(node)
      end

      #: (Prism::InterpolatedStringNode node) -> void
      def on_interpolated_string_node_enter(node)
        opening_loc = node.opening_loc || node.location
        closing_loc = node.closing_loc || node.parts.last&.location || node.location

        add_lines_range(opening_loc.start_line, closing_loc.start_line - 1)
      end

      #: (Prism::ArrayNode node) -> void
      def on_array_node_enter(node)
        add_simple_range(node)
      end

      #: (Prism::BlockNode node) -> void
      def on_block_node_enter(node)
        add_simple_range(node)
      end

      #: (Prism::CaseNode node) -> void
      def on_case_node_enter(node)
        add_simple_range(node)
      end

      #: (Prism::CaseMatchNode node) -> void
      def on_case_match_node_enter(node)
        add_simple_range(node)
      end

      #: (Prism::ClassNode node) -> void
      def on_class_node_enter(node)
        add_simple_range(node)
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_enter(node)
        add_simple_range(node)
      end

      #: (Prism::ForNode node) -> void
      def on_for_node_enter(node)
        add_simple_range(node)
      end

      #: (Prism::HashNode node) -> void
      def on_hash_node_enter(node)
        add_simple_range(node)
      end

      #: (Prism::SingletonClassNode node) -> void
      def on_singleton_class_node_enter(node)
        add_simple_range(node)
      end

      #: (Prism::UnlessNode node) -> void
      def on_unless_node_enter(node)
        add_simple_range(node)
      end

      #: (Prism::UntilNode node) -> void
      def on_until_node_enter(node)
        add_simple_range(node)
      end

      #: (Prism::WhileNode node) -> void
      def on_while_node_enter(node)
        add_simple_range(node)
      end

      #: (Prism::ElseNode node) -> void
      def on_else_node_enter(node)
        add_simple_range(node)
      end

      #: (Prism::EnsureNode node) -> void
      def on_ensure_node_enter(node)
        add_simple_range(node)
      end

      #: (Prism::BeginNode node) -> void
      def on_begin_node_enter(node)
        add_simple_range(node)
      end

      #: (Prism::DefNode node) -> void
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

      #: (Prism::CallNode node) -> void
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

      #: (Prism::LambdaNode node) -> void
      def on_lambda_node_enter(node)
        add_simple_range(node)
      end

      private

      #: -> void
      def push_comment_ranges
        # Group comments that are on consecutive lines and then push ranges for each group that has at least 2 comments
        @comments.chunk_while do |this, other|
          this.location.end_line + 1 == other.location.start_line && !this.trailing? && !other.trailing?
        end.each do |chunk|
          next if chunk.length == 1

          @response_builder << Interface::FoldingRange.new(
            start_line: chunk.first #: as !nil
              .location.start_line - 1,
            end_line: chunk.last #: as !nil
              .location.end_line - 1,
            kind: "comment",
          )
        end
      end

      #: -> void
      def emit_requires_range
        if @requires.length > 1
          @response_builder << Interface::FoldingRange.new(
            start_line: @requires.first #: as !nil
              .location.start_line - 1,
            end_line: @requires.last #: as !nil
              .location.end_line - 1,
            kind: "imports",
          )
        end

        @requires.clear
      end

      #: (Prism::CallNode node) -> bool
      def require?(node)
        message = node.message
        return false unless message == "require" || message == "require_relative"

        receiver = node.receiver
        return false unless receiver.nil? || receiver.slice == "Kernel"

        arguments = node.arguments&.arguments
        return false unless arguments

        arguments.length == 1 && arguments.first.is_a?(Prism::StringNode)
      end

      #: ((Prism::IfNode | Prism::InNode | Prism::RescueNode | Prism::WhenNode) node) -> void
      def add_statements_range(node)
        statements = node.statements
        return unless statements

        statement = statements.body.last
        return unless statement

        add_lines_range(node.location.start_line, statement.location.end_line)
      end

      #: (Prism::Node node) -> void
      def add_simple_range(node)
        location = node.location
        add_lines_range(location.start_line, location.end_line - 1)
      end

      #: (Integer start_line, Integer end_line) -> void
      def add_lines_range(start_line, end_line)
        emit_requires_range
        return if start_line >= end_line

        @response_builder << Interface::FoldingRange.new(
          start_line: start_line - 1,
          end_line: end_line - 1,
          kind: "region",
        )
      end
    end
  end
end
