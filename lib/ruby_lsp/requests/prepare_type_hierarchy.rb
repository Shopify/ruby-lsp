# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [prepare type hierarchy
    # request](https://microsoft.github.io/language-server-protocol/specification#textDocument_prepareTypeHierarchy)
    # displays the list of direct ancestors (supertypes) and descendants (subtypes) for the selected type.
    class PrepareTypeHierarchy < Request
      include Support::Common

      class << self
        #: -> Interface::TypeHierarchyOptions
        def provider
          Interface::TypeHierarchyOptions.new
        end
      end

      #: ((RubyDocument | ERBDocument) document, GlobalState global_state, Hash[Symbol, untyped] position) -> void
      def initialize(document, global_state, position)
        super()

        @document = document
        @graph = global_state.graph #: Rubydex::Graph
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
            Prism::SingletonClassNode,
          ],
        )

        node = context.node #: as (Prism::ConstantReadNode | Prism::ConstantPathNode | Prism::ConstantWriteNode | Prism::SingletonClassNode)?
        return unless node

        pair = name_and_nesting(node, context)
        return unless pair

        declaration = @graph.resolve_constant(pair.first, pair.last)
        return unless declaration.is_a?(Rubydex::Namespace)

        primary = declaration.definitions.first
        return unless primary

        [
          primary.to_lsp_type_hierarchy_item(
            declaration.name,
            detail: declaration.lsp_type_hierarchy_detail,
          ),
        ]
      end

      private

      # Returns the `(name, nesting)` pair to pass to `Rubydex::Graph#resolve_constant`, covering three cases:
      #
      #: ((Prism::ConstantReadNode | Prism::ConstantPathNode | Prism::ConstantWriteNode | Prism::SingletonClassNode), NodeContext) -> [String, Array[String]]?
      def name_and_nesting(node, context)
        parent = context.parent
        nesting = context.nesting

        singleton_node = singleton_class_node_for(node, parent)
        return singleton_lookup(singleton_node, nesting) if singleton_node

        target = parent ? determine_target(node, parent, @position) : node
        [target.slice, nesting]
      end

      # Ensures that we're returning the target of the singleton class block regardless of whether the cursor is on the
      # `class` keyword or the constant reference for the target
      #: ((Prism::ConstantReadNode | Prism::ConstantPathNode | Prism::ConstantWriteNode | Prism::SingletonClassNode), Prism::Node?) -> Prism::SingletonClassNode?
      def singleton_class_node_for(node, parent)
        return node if node.is_a?(Prism::SingletonClassNode)
        return unless parent.is_a?(Prism::SingletonClassNode) && parent.expression == node

        parent
      end

      # Builds the synthesized singleton class name (e.g. `Foo::<Foo>`) for a `class << X` block, together with the
      # outer lexical nesting. `NodeContext` already appends a `<ClassName>` marker as the last element of the nesting
      # whenever the cursor sits inside (or on) a `SingletonClassNode`, so we drop that marker to obtain the scope in
      # which the singleton should be resolved.
      #: (Prism::SingletonClassNode, Array[String]) -> [String, Array[String]]?
      def singleton_lookup(singleton_node, nesting)
        outer = nesting[0...-1] || []

        case expression = singleton_node.expression
        when Prism::SelfNode
          name = nesting.last
          return unless name

          [name, outer]
        when Prism::ConstantReadNode, Prism::ConstantPathNode
          name = constant_name(expression)
          return unless name

          unqualified = name.split("::").last #: as !nil
          ["#{name}::<#{unqualified}>", outer]
        end
      end
    end
  end
end
