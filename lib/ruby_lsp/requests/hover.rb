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
          Prism::CallNode,
          Prism::ConstantReadNode,
          Prism::ConstantWriteNode,
          Prism::ConstantPathNode,
        ],
        T::Array[T.class_of(Prism::Node)],
      )

      sig { override.returns(ResponseType) }
      attr_reader :_response

      sig do
        params(
          index: RubyIndexer::Index,
          nesting: T::Array[String],
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(index, nesting, dispatcher)
        @index = index
        @nesting = nesting
        @_response = T.let(nil, ResponseType)

        super(dispatcher)
        dispatcher.register(
          self,
          :on_constant_read_node_enter,
          :on_constant_write_node_enter,
          :on_constant_path_node_enter,
          :on_call_node_enter,
        )
      end

      sig { override.params(addon: Addon).returns(T.nilable(Listener[ResponseType])) }
      def initialize_external_listener(addon)
        addon.create_hover_listener(@nesting, @index, @dispatcher)
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

      sig { params(node: Prism::ConstantReadNode).void }
      def on_constant_read_node_enter(node)
        return if DependencyDetector.instance.typechecker

        generate_hover(node.slice, node.location)
      end

      sig { params(node: Prism::ConstantWriteNode).void }
      def on_constant_write_node_enter(node)
        return if DependencyDetector.instance.typechecker

        generate_hover(node.name.to_s, node.name_loc)
      end

      sig { params(node: Prism::ConstantPathNode).void }
      def on_constant_path_node_enter(node)
        return if DependencyDetector.instance.typechecker

        generate_hover(node.slice, node.location)
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_enter(node)
        return if DependencyDetector.instance.typechecker
        return unless self_receiver?(node)

        message = node.message
        return unless message

        target_method = @index.resolve_method(message, @nesting.join("::"))
        return unless target_method

        location = target_method.location

        @_response = Interface::Hover.new(
          range: range_from_location(location),
          contents: markdown_from_index_entries(message, target_method),
        )
      end

      private

      sig { params(name: String, location: Prism::Location).void }
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
