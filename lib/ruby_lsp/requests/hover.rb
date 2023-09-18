# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Hover demo](../../hover.gif)
    #
    # The [hover request](https://microsoft.github.io/language-server-protocol/specification#textDocument_hover)
    # displays the documentation for the symbol currently under the cursor.
    #
    # # Example
    #
    # ```ruby
    # String # -> Hovering over the class reference will show all declaration locations and the documentation
    # ```
    class Hover < ExtensibleListener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T.nilable(Interface::Hover) } }

      ALLOWED_TARGETS = T.let(
        [
          SyntaxTree::Const,
          SyntaxTree::Command,
          SyntaxTree::CallNode,
          SyntaxTree::ConstPathRef,
        ],
        T::Array[T.class_of(SyntaxTree::Node)],
      )

      sig { override.returns(ResponseType) }
      attr_reader :_response

      sig do
        params(
          index: RubyIndexer::Index,
          nesting: T::Array[String],
          emitter: EventEmitter,
          message_queue: Thread::Queue,
        ).void
      end
      def initialize(index, nesting, emitter, message_queue)
        @nesting = nesting
        @index = index
        @_response = T.let(nil, ResponseType)

        super(emitter, message_queue)
        emitter.register(self, :on_const_path_ref, :on_const)
      end

      sig { override.params(extension: RubyLsp::Extension).returns(T.nilable(Listener[ResponseType])) }
      def initialize_external_listener(extension)
        extension.create_hover_listener(@nesting, @index, @emitter, @message_queue)
      end

      # Merges responses from other hover listeners
      sig { override.params(other: Listener[ResponseType]).returns(T.self_type) }
      def merge_response!(other)
        other_response = other.response
        return self unless other_response

        if @_response.nil?
          @_response = other.response
        else
          @_response.contents.value << "\n\n" << other_response.contents.value
        end

        self
      end

      sig { params(node: SyntaxTree::ConstPathRef).void }
      def on_const_path_ref(node)
        return if DependencyDetector::HAS_TYPECHECKER

        name = full_constant_name(node)
        generate_hover(name, node)
      end

      sig { params(node: SyntaxTree::Const).void }
      def on_const(node)
        return if DependencyDetector::HAS_TYPECHECKER

        generate_hover(node.value, node)
      end

      private

      sig { params(name: String, node: SyntaxTree::Node).void }
      def generate_hover(name, node)
        entries = @index.resolve(name, @nesting)
        return unless entries

        @_response = Interface::Hover.new(
          range: range_from_syntax_tree_node(node),
          contents: markdown_from_index_entries(name, entries),
        )
      end
    end
  end
end
