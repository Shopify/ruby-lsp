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
    class FoldingRanges < BaseRequest
      extend T::Sig

      sig { params(document: Document).void }
      def initialize(document)
        super

        @ranges = T.let([], T::Array[Interface::FoldingRange])
        @requires = T.let([], T::Array[YARP::CallNode])
      end

      sig { override.returns(T.all(T::Array[Interface::FoldingRange], Object)) }
      def run
        visit(@document.tree)
        push_comment_ranges
        emit_requires_range
        @ranges
      end

      private

      sig { void }
      def push_comment_ranges
        # Group comments that are on consecutive lines and then push ranges for each group that has at least 2 comments
        @document.parse_result.comments.chunk_while do |this, other|
          this.location.end_line + 1 == other.location.start_line
        end.each do |chunk|
          next if chunk.length == 1

          @ranges << Interface::FoldingRange.new(
            start_line: chunk.first.location.start_line - 1,
            end_line: chunk.last.location.end_line - 1,
            kind: "comment",
          )
        end
      end

      sig { void }
      def emit_requires_range
        if @requires.length > 1
          @ranges << Interface::FoldingRange.new(
            start_line: T.must(@requires.first).location.start_line - 1,
            end_line: T.must(@requires.last).location.end_line - 1,
            kind: "imports",
          )
        end

        @requires.clear
      end

      sig { override.params(node: T.nilable(YARP::Node)).void }
      def visit(node)
        emit_requires_range unless node.is_a?(YARP::CallNode)

        case node
        when YARP::ArrayNode, YARP::BlockNode, YARP::CaseNode, YARP::ClassNode, YARP::ForNode, YARP::HashNode,
          YARP::ModuleNode, YARP::SingletonClassNode, YARP::UnlessNode, YARP::UntilNode, YARP::WhileNode,
          YARP::ElseNode, YARP::EnsureNode, YARP::BeginNode

          location = node.location
          add_lines_range(location.start_line, location.end_line - 1)
        when YARP::InterpolatedStringNode
          opening_loc = node.opening_loc
          closing_loc = node.closing_loc

          add_lines_range(opening_loc.start_line, closing_loc.end_line - 1) if opening_loc && closing_loc
        when YARP::IfNode, YARP::InNode, YARP::RescueNode, YARP::WhenNode
          add_statements_range(node)
        when YARP::CallNode
          # If we find a require, don't visit the child nodes (prevent `super`), so that we can keep accumulating into
          # the `@requires` array and then push the range whenever we find a node that isn't a CallNode
          if require?(node)
            @requires << node
            return
          end

          location = node.location
          add_lines_range(location.start_line, location.end_line - 1)

          receiver = node.receiver
          visit(receiver) if receiver && !same_lines?(receiver, node)

          block = node.block
          if block
            same_lines?(block, node) ? visit(block.body) : visit(block)
          end

          arguments = node.arguments
          visit(arguments) if arguments && !same_lines?(arguments, node)

          return
        when YARP::DefNode
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

          visit(node.body)
          return
        when YARP::StringConcatNode
          add_string_concat(node)
          return
        end

        super
      end

      sig { params(node: YARP::CallNode).returns(T::Boolean) }
      def require?(node)
        message = node.message
        return false unless message == "require" || message == "require_relative"

        receiver = node.receiver
        return false unless receiver.nil? || receiver.slice == "Kernel"

        arguments = node.arguments&.arguments
        return false unless arguments

        arguments.length == 1 && arguments.first.is_a?(YARP::StringNode)
      end

      sig { params(node: YARP::Node, other: YARP::Node).returns(T::Boolean) }
      def same_lines?(node, other)
        loc = node.location
        other_loc = other.location

        loc.start_line == other_loc.start_line && loc.end_line == other_loc.end_line
      end

      sig { params(node: T.any(YARP::IfNode, YARP::InNode, YARP::RescueNode, YARP::WhenNode)).void }
      def add_statements_range(node)
        statements = node.statements
        return unless statements

        body = statements.body
        return if body.empty?

        add_lines_range(node.location.start_line, T.must(body.last).location.end_line)
      end

      sig { params(node: YARP::StringConcatNode).void }
      def add_string_concat(node)
        left = T.let(node.left, YARP::Node)
        left = left.left while left.is_a?(YARP::StringConcatNode)

        add_lines_range(left.location.start_line, node.right.location.end_line - 1)
      end

      sig { params(start_line: Integer, end_line: Integer).void }
      def add_lines_range(start_line, end_line)
        return if start_line >= end_line

        @ranges << Interface::FoldingRange.new(
          start_line: start_line - 1,
          end_line: end_line - 1,
          kind: "region",
        )
      end
    end
  end
end
