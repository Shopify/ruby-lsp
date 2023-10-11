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

      sig { params(comments: T::Array[YARP::Comment], emitter: EventEmitter, queue: Thread::Queue).void }
      def initialize(comments, emitter, queue)
        super(emitter, queue)

        @_response = T.let([], ResponseType)
        @requires = T.let([], T::Array[YARP::CallNode])
        @finalized_response = T.let(false, T::Boolean)
        @comments = comments

        emitter.register(
          self,
          :on_if,
          :on_in,
          :on_rescue,
          :on_when,
          :on_interpolated_string,
          :on_array,
          :on_block,
          :on_case,
          :on_class,
          :on_module,
          :on_for,
          :on_hash,
          :on_singleton_class,
          :on_unless,
          :on_until,
          :on_while,
          :on_else,
          :on_ensure,
          :on_begin,
          :on_string_concat,
          :on_def,
          :on_call,
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

      sig { params(node: YARP::IfNode).void }
      def on_if(node)
        add_statements_range(node)
      end

      sig { params(node: YARP::InNode).void }
      def on_in(node)
        add_statements_range(node)
      end

      sig { params(node: YARP::RescueNode).void }
      def on_rescue(node)
        add_statements_range(node)
      end

      sig { params(node: YARP::WhenNode).void }
      def on_when(node)
        add_statements_range(node)
      end

      sig { params(node: YARP::InterpolatedStringNode).void }
      def on_interpolated_string(node)
        opening_loc = node.opening_loc
        closing_loc = node.closing_loc

        add_lines_range(opening_loc.start_line, closing_loc.end_line - 1) if opening_loc && closing_loc
      end

      sig { params(node: YARP::ArrayNode).void }
      def on_array(node)
        add_simple_range(node)
      end

      sig { params(node: YARP::BlockNode).void }
      def on_block(node)
        add_simple_range(node)
      end

      sig { params(node: YARP::CaseNode).void }
      def on_case(node)
        add_simple_range(node)
      end

      sig { params(node: YARP::ClassNode).void }
      def on_class(node)
        add_simple_range(node)
      end

      sig { params(node: YARP::ModuleNode).void }
      def on_module(node)
        add_simple_range(node)
      end

      sig { params(node: YARP::ForNode).void }
      def on_for(node)
        add_simple_range(node)
      end

      sig { params(node: YARP::HashNode).void }
      def on_hash(node)
        add_simple_range(node)
      end

      sig { params(node: YARP::SingletonClassNode).void }
      def on_singleton_class(node)
        add_simple_range(node)
      end

      sig { params(node: YARP::UnlessNode).void }
      def on_unless(node)
        add_simple_range(node)
      end

      sig { params(node: YARP::UntilNode).void }
      def on_until(node)
        add_simple_range(node)
      end

      sig { params(node: YARP::WhileNode).void }
      def on_while(node)
        add_simple_range(node)
      end

      sig { params(node: YARP::ElseNode).void }
      def on_else(node)
        add_simple_range(node)
      end

      sig { params(node: YARP::EnsureNode).void }
      def on_ensure(node)
        add_simple_range(node)
      end

      sig { params(node: YARP::BeginNode).void }
      def on_begin(node)
        add_simple_range(node)
      end

      sig { params(node: YARP::StringConcatNode).void }
      def on_string_concat(node)
        left = T.let(node.left, YARP::Node)
        left = left.left while left.is_a?(YARP::StringConcatNode)

        add_lines_range(left.location.start_line, node.right.location.end_line - 1)
      end

      sig { params(node: YARP::DefNode).void }
      def on_def(node)
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

      sig { params(node: YARP::CallNode).void }
      def on_call(node)
        # If we find a require, don't visit the child nodes (prevent `super`), so that we can keep accumulating into
        # the `@requires` array and then push the range whenever we find a node that isn't a CallNode
        if require?(node)
          @requires << node
          return
        end

        location = node.location
        add_lines_range(location.start_line, location.end_line - 1)
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

      sig { params(node: T.any(YARP::IfNode, YARP::InNode, YARP::RescueNode, YARP::WhenNode)).void }
      def add_statements_range(node)
        statements = node.statements
        return unless statements

        body = statements.body
        return if body.empty?

        add_lines_range(node.location.start_line, T.must(body.last).location.end_line)
      end

      sig { params(node: YARP::Node).void }
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
