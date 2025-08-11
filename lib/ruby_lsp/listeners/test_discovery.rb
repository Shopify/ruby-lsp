# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    # @abstract
    class TestDiscovery
      include Requests::Support::Common

      DYNAMIC_REFERENCE_MARKER = "<dynamic_reference>"

      #: (ResponseBuilders::TestCollection response_builder, GlobalState global_state, URI::Generic uri) -> void
      def initialize(response_builder, global_state, uri)
        @response_builder = response_builder
        @uri = uri
        @index = global_state.index #: RubyIndexer::Index
        @visibility_stack = [:public] #: Array[Symbol]
        @nesting = [] #: Array[String]
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_enter(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        @visibility_stack << :public

        name = constant_name(node.constant_path)
        name ||= name_with_dynamic_reference(node.constant_path)

        @nesting << name
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_leave(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        @visibility_stack.pop
        @nesting.pop
      end

      #: (Prism::ClassNode node) -> void
      def on_class_node_leave(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        @visibility_stack.pop
        @nesting.pop
      end

      private

      #: (Prism::Dispatcher, *Symbol) -> void
      def register_events(dispatcher, *events)
        unique_events = events.dup.push(
          :on_class_node_leave,
          :on_module_node_enter,
          :on_module_node_leave,
        )

        unique_events.uniq!
        dispatcher.register(self, *unique_events)
      end

      #: (String? name) -> String
      def calc_fully_qualified_name(name)
        RubyIndexer::Index.actual_nesting(@nesting, name).join("::")
      end

      #: (Prism::ClassNode node, String fully_qualified_name) -> Array[String]
      def calc_attached_ancestors(node, fully_qualified_name)
        superclass = node.superclass

        begin
          ancestors = @index.linearized_ancestors_of(fully_qualified_name)
          # If the project has no bundle and a test class inherits from `Minitest::Test`, the linearized ancestors will
          # not include the parent class because we never indexed it in the first place. Here we add the superclass
          # directly, so that we can support running tests in projects without a bundle
          return ancestors if ancestors.length > 1

          # If all we found is the class itself, then manually include the parent class
          if ancestors.first == fully_qualified_name && superclass
            return [*ancestors, superclass.slice]
          end

          ancestors
        rescue RubyIndexer::Index::NonExistingNamespaceError
          # When there are dynamic parts in the constant path, we will not have indexed the namespace. We can still
          # provide test functionality if the class inherits directly from Test::Unit::TestCase or Minitest::Test
          [superclass&.slice].compact
        end
      end

      #: (Prism::ConstantPathNode | Prism::ConstantReadNode | Prism::ConstantPathTargetNode | Prism::CallNode | Prism::MissingNode node) -> String
      def name_with_dynamic_reference(node)
        slice = node.slice
        slice.gsub(/((?<=::)|^)[a-z]\w*/, DYNAMIC_REFERENCE_MARKER)
      end

      #: (Prism::ClassNode node) { (String name, Array[String] ancestors) -> void } -> void
      def with_test_ancestor_tracking(node, &block)
        @visibility_stack << :public
        name = constant_name(node.constant_path)
        name ||= name_with_dynamic_reference(node.constant_path)

        fully_qualified_name = calc_fully_qualified_name(name)
        attached_ancestors = calc_attached_ancestors(node, fully_qualified_name)

        block.call(fully_qualified_name, attached_ancestors)

        @nesting << name
      end
    end
  end
end
