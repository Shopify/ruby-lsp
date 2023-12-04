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
        @rdoc_driver = T.let(RDoc::RI::Driver.new, RDoc::RI::Driver)
        @rdoc_formatter = T.let(RDoc::Markup::ToMarkdown.new, RDoc::Markup::ToMarkdown)

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
        indexed_contents = nil

        if entries
          # We should only show hover for private constants if the constant is defined in the same namespace as the
          # reference
          first_entry = T.must(entries.first)
          unless first_entry.visibility == :private && first_entry.name != "#{@nesting.join("::")}::#{name}"
            indexed_contents = markdown_from_index_entries(name, entries)
          end
        end

        ri_contents = generate_hover_from_rdoc(name, entries)

        contents = if ri_contents && indexed_contents
          Interface::MarkupContent.new(
            kind: "markdown",
            value: "#{ri_contents.value}\n\n---\n\n#{indexed_contents.value}",
          )
        else
          indexed_contents || ri_contents
        end

        return unless contents

        @_response = Interface::Hover.new(
          range: range_from_location(location),
          contents: contents,
        )
      end

      sig do
        params(
          name: String,
          entries: T.nilable(T::Array[RubyIndexer::Entry]),
        ).returns(T.nilable(Interface::MarkupContent))
      end
      def generate_hover_from_rdoc(name, entries)
        if entries
          first_entry = T.must(entries.first)
          name = first_entry.name
        end

        expand_name = @rdoc_driver.expand_name(name)
        found, klasses, includes, extends = @rdoc_driver.classes_and_includes_and_extends_for(expand_name)

        unless found.empty?
          ri_doc = @rdoc_driver.class_document(expand_name, found, klasses, includes, extends)
          Interface::MarkupContent.new(
            kind: "markdown",
            value: ri_doc.accept(@rdoc_formatter),
          )
        end
      rescue RDoc::RI::Driver::NotFoundError
        nil
      end
    end
  end
end
