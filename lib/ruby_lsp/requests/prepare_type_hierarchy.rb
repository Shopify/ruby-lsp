# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [prepare type hierarchy
    # request](https://microsoft.github.io/language-server-protocol/specification#textDocument_prepareTypeHierarchy)
    # displays the list of ancestors (supertypes) and descendants (subtypes) for the selected type.
    #
    # Currently only supports supertypes due to a limitation of the index.
    class PrepareTypeHierarchy < Request
      include Support::Common

      class << self
        #: -> Interface::TypeHierarchyOptions
        def provider
          Interface::TypeHierarchyOptions.new
        end
      end

      #: ((RubyDocument | ERBDocument) document, RubyIndexer::Index index, Hash[Symbol, untyped] position) -> void
      def initialize(document, index, position)
        super()

        @document = document
        @index = index
        @position = position
      end

      # @override
      #: -> Array[Interface::TypeHierarchyItem]?
      def perform
        context = @document.locate_node(
          @position,
          node_types: [
            Prism::ConstantReadNode,
            Prism::ConstantWriteNode,
            Prism::ConstantPathNode,
          ],
        )

        node = context.node
        parent = context.parent
        return unless node && parent

        target = determine_target(node, parent, @position)
        entries = @index.resolve(target.slice, context.nesting)
        return unless entries

        # While the spec allows for multiple entries, VSCode seems to only support one
        # We'll just return the first one for now
        first_entry = entries.first #: as !nil
        range = range_from_location(first_entry.location)

        [
          Interface::TypeHierarchyItem.new(
            name: first_entry.name,
            kind: kind_for_entry(first_entry),
            uri: first_entry.uri.to_s,
            range: range,
            selection_range: range,
          ),
        ]
      end
    end
  end
end
