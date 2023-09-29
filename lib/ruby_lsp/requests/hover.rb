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
          YARP::CallNode,
          YARP::ConstantReadNode,
          YARP::ConstantWriteNode,
          YARP::ConstantPathNode,
        ],
        T::Array[T.class_of(YARP::Node)],
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
        @index = index
        @nesting = nesting
        @_response = T.let(nil, ResponseType)

        super(emitter, message_queue)
        emitter.register(self, :on_constant_read, :on_constant_write, :on_constant_path)
      end

      sig { override.params(addon: Addon).returns(T.nilable(Listener[ResponseType])) }
      def initialize_external_listener(addon)
        addon.create_hover_listener(@nesting, @index, @emitter, @message_queue)
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

      sig { params(node: YARP::ConstantReadNode).void }
      def on_constant_read(node)
        return if DependencyDetector.instance.typechecker

        generate_hover(node.slice, node.location)
      end

      sig { params(node: YARP::ConstantWriteNode).void }
      def on_constant_write(node)
        return if DependencyDetector.instance.typechecker

        generate_hover(node.name.to_s, node.name_loc)
      end

      sig { params(node: YARP::ConstantPathNode).void }
      def on_constant_path(node)
        return if DependencyDetector.instance.typechecker

        generate_hover(node.slice, node.location)
      end

      private

      sig { params(name: String, location: YARP::Location).void }
      def generate_hover(name, location)
        entries = @index.resolve(name, @nesting)
        return unless entries

        # We should only show hover for private constants if the constant is defined in the same namespace as the
        # reference
        first_entry = T.must(entries.first)
        return if first_entry.visibility == :private && first_entry.name != "#{@nesting.join("::")}::#{name}"

        @_response = Interface::Hover.new(
          range: range_from_location(location),
          contents: markdown_from_index_entries(name, entries),
        )
      end
    end
  end
end
