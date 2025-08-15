# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class SpecStyle < TestDiscovery
      class Group
        #: String
        attr_reader :id

        #: (String) -> void
        def initialize(id)
          @id = id
        end
      end

      class ClassGroup < Group; end
      class DescribeGroup < Group; end

      #: (ResponseBuilders::TestCollection, GlobalState, Prism::Dispatcher, URI::Generic) -> void
      def initialize(response_builder, global_state, dispatcher, uri)
        super(response_builder, global_state, uri)

        @spec_group_id_stack = [] #: Array[Group?]

        register_events(
          dispatcher,
          :on_class_node_enter,
          :on_call_node_enter,
          :on_call_node_leave,
        )
      end

      #: (Prism::ClassNode) -> void
      def on_class_node_enter(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        with_test_ancestor_tracking(node) do |name, ancestors|
          @spec_group_id_stack << (ancestors.include?("Minitest::Spec") ? ClassGroup.new(name) : nil)
        end
      end

      #: (Prism::ClassNode) -> void
      def on_class_node_leave(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        @spec_group_id_stack.pop
        super
      end

      #: (Prism::ModuleNode) -> void
      def on_module_node_enter(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        @spec_group_id_stack << nil
        super
      end

      #: (Prism::ModuleNode) -> void
      def on_module_node_leave(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        @spec_group_id_stack.pop
        super
      end

      #: (Prism::CallNode) -> void
      def on_call_node_enter(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        case node.name
        when :describe
          handle_describe(node)
        when :it, :specify
          handle_example(node) if in_spec_context?
        end
      end

      #: (Prism::CallNode) -> void
      def on_call_node_leave(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        return unless node.name == :describe && !node.receiver

        current_group = @spec_group_id_stack.last
        return unless current_group.is_a?(DescribeGroup)

        description = extract_description(node)
        return unless description && current_group.id.end_with?(description)

        @spec_group_id_stack.pop
      end

      private

      #: (Prism::CallNode) -> void
      def handle_describe(node)
        # Describes will include the nesting of all classes and all outer describes as part of its ID, unlike classes
        # that ignore describes
        return if node.block.nil?

        description = extract_description(node)
        return unless description

        parent = latest_group
        return unless parent

        id = case parent
        when Requests::Support::TestItem
          "#{parent.id}::#{description}"
        else
          description
        end

        test_item = Requests::Support::TestItem.new(
          id,
          description,
          @uri,
          range_from_node(node),
          framework: :minitest,
        )

        parent.add(test_item)
        @response_builder.add_code_lens(test_item)
        @spec_group_id_stack << DescribeGroup.new(id)
      end

      #: (Prism::CallNode) -> void
      def handle_example(node)
        description = extract_it_description(node)
        line = node.location.start_line - 1
        parent = latest_group
        return unless parent.is_a?(Requests::Support::TestItem)

        id = "#{parent.id}##{format("test_%04d_%s", line, description)}"

        test_item = Requests::Support::TestItem.new(
          id,
          description,
          @uri,
          range_from_node(node),
          framework: :minitest,
        )

        parent.add(test_item)
        @response_builder.add_code_lens(test_item)
      end

      #: (Prism::CallNode) -> String?
      def extract_description(node)
        arguments = node.arguments&.arguments
        return unless arguments

        parts = arguments.map { |arg| extract_argument_content(arg) }
        return if parts.empty?

        parts.join("::")
      end

      #: (Prism::CallNode) -> String
      def extract_it_description(node)
        # Minitest formats the descriptions into test method names by using the count of examples with the description
        # We are not guaranteed to discover examples in the exact order using static analysis, so we use the line number
        # instead. Note that anonymous examples mixed with meta-programming will not be handled correctly
        first_argument = node.arguments&.arguments&.first
        return "anonymous" unless first_argument

        extract_argument_content(first_argument) || "anonymous"
      end

      #: (Prism::Node) -> String?
      def extract_argument_content(arg)
        case arg
        when Prism::StringNode
          arg.content
        when Prism::SymbolNode
          arg.value
        when Prism::ConstantReadNode, Prism::ConstantPathNode
          constant_name(arg)
        else
          arg.slice
        end
      end

      #: -> (Requests::Support::TestItem | ResponseBuilders::TestCollection)?
      def latest_group
        # If we haven't found anything yet, then return the response builder
        return @response_builder if @spec_group_id_stack.compact.empty?
        # If we found something that isn't a group last, then we're inside a random module or class, but not a spec
        # group
        return unless @spec_group_id_stack.last

        # Specs using at least one class as a group require special handling
        closest_class_index = @spec_group_id_stack.rindex { |i| i.is_a?(ClassGroup) }

        if closest_class_index
          first_class_index = @spec_group_id_stack.index { |i| i.is_a?(ClassGroup) } #: as !nil
          first_class = @spec_group_id_stack[first_class_index] #: as !nil
          item = @response_builder[first_class.id] #: as !nil

          # Descend into child items from the beginning all the way to the latest class group, ignoring describes
          @spec_group_id_stack[first_class_index + 1..closest_class_index] #: as !nil
            .each do |group|
            next unless group.is_a?(ClassGroup)

            item = item[group.id] #: as !nil
          end

          # From the class forward, we must take describes into account
          @spec_group_id_stack[closest_class_index + 1..] #: as !nil
            .each do |group|
            next unless group

            item = item[group.id] #: as !nil
          end

          return item
        end

        # Specs only using describes
        first_group_index = @spec_group_id_stack.index { |i| i.is_a?(DescribeGroup) }
        return unless first_group_index

        first_group = @spec_group_id_stack[first_group_index] #: as !nil
        item = @response_builder[first_group.id] #: as !nil

        @spec_group_id_stack[first_group_index + 1..] #: as !nil
          .each do |group|
          next unless group.is_a?(DescribeGroup)

          item = item[group.id] #: as !nil
        end

        item
      end

      #: -> bool
      def in_spec_context?
        @nesting.empty? || @spec_group_id_stack.any? { |id| id }
      end
    end
  end
end
