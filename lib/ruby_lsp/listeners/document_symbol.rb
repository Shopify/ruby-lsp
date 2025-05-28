# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class DocumentSymbol
      include Requests::Support::Common

      ATTR_ACCESSORS = [:attr_reader, :attr_writer, :attr_accessor].freeze #: Array[Symbol]

      #: (ResponseBuilders::DocumentSymbol response_builder, URI::Generic uri, Prism::Dispatcher dispatcher) -> void
      def initialize(response_builder, uri, dispatcher)
        @response_builder = response_builder
        @uri = uri
        @current_visibility = T.let(:public, Symbol)

        dispatcher.register(
          self,
          :on_class_node_enter,
          :on_class_node_leave,
          :on_call_node_enter,
          :on_call_node_leave,
          :on_constant_path_write_node_enter,
          :on_constant_write_node_enter,
          :on_constant_path_or_write_node_enter,
          :on_constant_path_operator_write_node_enter,
          :on_constant_path_and_write_node_enter,
          :on_constant_or_write_node_enter,
          :on_constant_operator_write_node_enter,
          :on_constant_and_write_node_enter,
          :on_constant_target_node_enter,
          :on_constant_path_target_node_enter,
          :on_def_node_enter,
          :on_def_node_leave,
          :on_module_node_enter,
          :on_module_node_leave,
          :on_instance_variable_write_node_enter,
          :on_instance_variable_target_node_enter,
          :on_instance_variable_operator_write_node_enter,
          :on_instance_variable_or_write_node_enter,
          :on_instance_variable_and_write_node_enter,
          :on_class_variable_write_node_enter,
          :on_singleton_class_node_enter,
          :on_singleton_class_node_leave,
          :on_alias_method_node_enter,
        )
      end

      #: (Prism::ClassNode node) -> void
      def on_class_node_enter(node)
        @response_builder << create_document_symbol(
          name: node.constant_path.location.slice,
          kind: Constant::SymbolKind::CLASS,
          range_location: node.location,
          selection_range_location: node.constant_path.location,
        )
      end

      #: (Prism::ClassNode node) -> void
      def on_class_node_leave(node)
        @response_builder.pop
      end

      #: (Prism::SingletonClassNode node) -> void
      def on_singleton_class_node_enter(node)
        expression = node.expression

        @response_builder << create_document_symbol(
          name: "<< #{expression.slice}",
          kind: Constant::SymbolKind::NAMESPACE,
          range_location: node.location,
          selection_range_location: expression.location,
        )
      end

      #: (Prism::SingletonClassNode node) -> void
      def on_singleton_class_node_leave(node)
        @response_builder.pop
      end

      #: (Prism::CallNode node) -> void
      def on_call_node_enter(node)
        node_name = node.name

        # TODO: Pull into a constant and look more closely at the CodeLens implementation
        # TODO: Is this disgusting? It creates an "empty" container but that means I'm changing the hierarchy in the outline.
        # TODO: Is this a hack? I want to return and not interrupt the rest of the response builder doing its thing.
        if [:private, :protected, :public].include?(node_name) && node.arguments.nil?
          @current_visibility = node_name
          return
        end

        if ATTR_ACCESSORS.include?(node_name)
          handle_attr_accessor(node)
        elsif node_name == :alias_method
          handle_alias_method(node)
        elsif node_name == :namespace
          handle_rake_namespace(node)
        elsif node_name == :task
          handle_rake_task(node)
        end
      end

      #: (Prism::CallNode node) -> void
      def on_call_node_leave(node)
        # TODO: Currently exiting the container here using the same `pop` as above but is this correct in this context?
        # TODO: Investigate how CodeLens is handling this. I can see it doing `#pop` off the modifier constant.
        if node.name == :public && node.arguments.nil?
          @current_visibility = :public
        end
        # No pop for private/protected anymore
        return unless rake?

        if node.name == :namespace && !node.receiver
          @response_builder.pop
        end
      end

      #: (Prism::ConstantPathWriteNode node) -> void
      def on_constant_path_write_node_enter(node)
        create_document_symbol(
          name: node.target.location.slice,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.target.location,
        )
      end

      #: (Prism::ConstantWriteNode node) -> void
      def on_constant_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.name_loc,
        )
      end

      #: (Prism::ConstantPathAndWriteNode node) -> void
      def on_constant_path_and_write_node_enter(node)
        create_document_symbol(
          name: node.target.location.slice,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.target.location,
        )
      end

      #: (Prism::ConstantPathOrWriteNode node) -> void
      def on_constant_path_or_write_node_enter(node)
        create_document_symbol(
          name: node.target.location.slice,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.target.location,
        )
      end

      #: (Prism::ConstantPathOperatorWriteNode node) -> void
      def on_constant_path_operator_write_node_enter(node)
        create_document_symbol(
          name: node.target.location.slice,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.target.location,
        )
      end

      #: (Prism::ConstantOrWriteNode node) -> void
      def on_constant_or_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.name_loc,
        )
      end

      #: (Prism::ConstantAndWriteNode node) -> void
      def on_constant_and_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.name_loc,
        )
      end

      #: (Prism::ConstantOperatorWriteNode node) -> void
      def on_constant_operator_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.name_loc,
        )
      end

      #: (Prism::ConstantTargetNode node) -> void
      def on_constant_target_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.location,
        )
      end

      #: (Prism::ConstantPathTargetNode node) -> void
      def on_constant_path_target_node_enter(node)
        create_document_symbol(
          name: node.slice,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.location,
        )
      end

      #: (Prism::DefNode node) -> void
      def on_def_node_leave(node)
        @response_builder.pop
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_enter(node)
        @response_builder << create_document_symbol(
          name: node.constant_path.location.slice,
          kind: Constant::SymbolKind::MODULE,
          range_location: node.location,
          selection_range_location: node.constant_path.location,
        )
      end

      #: (Prism::DefNode node) -> void
      def on_def_node_enter(node)
        receiver = node.receiver
        previous_symbol = @response_builder.last

        if receiver.is_a?(Prism::SelfNode)
          name = "self.#{node.name}"
          kind = Constant::SymbolKind::FUNCTION
        elsif previous_symbol.is_a?(Interface::DocumentSymbol) && previous_symbol.name.start_with?("<<")
          name = node.name.to_s
          kind = Constant::SymbolKind::FUNCTION
        else
          name = node.name.to_s
          kind = name == "initialize" ? Constant::SymbolKind::CONSTRUCTOR : Constant::SymbolKind::METHOD
        end

        # TODO: Use the stuff we set up in the `on_call_node_enter` method to prefix the modifier.
        # This can definitely be tidied up, if only because it's a nested `if` statement and I'm reassigning `name`. Grim.
        # Not really sure I really understand the current/previous visibility stuff, just copying the bit above.
        case @current_visibility
        when :private
          name = "(private) #{name}"
        when :protected
          name = "(protected) #{name}"
        end

        symbol = create_document_symbol(
          name: name,
          kind: kind,
          range_location: node.location,
          selection_range_location: node.name_loc,
        )

        @response_builder << symbol
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_leave(node)
        @response_builder.pop
      end

      #: (Prism::ClassVariableWriteNode node) -> void
      def on_class_variable_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::VARIABLE,
          range_location: node.name_loc,
          selection_range_location: node.name_loc,
        )
      end

      #: (Prism::InstanceVariableWriteNode node) -> void
      def on_instance_variable_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::FIELD,
          range_location: node.name_loc,
          selection_range_location: node.name_loc,
        )
      end

      #: (Prism::InstanceVariableTargetNode node) -> void
      def on_instance_variable_target_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::FIELD,
          range_location: node.location,
          selection_range_location: node.location,
        )
      end

      #: (Prism::InstanceVariableOperatorWriteNode node) -> void
      def on_instance_variable_operator_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::FIELD,
          range_location: node.name_loc,
          selection_range_location: node.name_loc,
        )
      end

      #: (Prism::InstanceVariableOrWriteNode node) -> void
      def on_instance_variable_or_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::FIELD,
          range_location: node.name_loc,
          selection_range_location: node.name_loc,
        )
      end

      #: (Prism::InstanceVariableAndWriteNode node) -> void
      def on_instance_variable_and_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::FIELD,
          range_location: node.name_loc,
          selection_range_location: node.name_loc,
        )
      end

      #: (Prism::AliasMethodNode node) -> void
      def on_alias_method_node_enter(node)
        new_name_node = node.new_name
        return unless new_name_node.is_a?(Prism::SymbolNode)

        name = new_name_node.value
        return unless name

        create_document_symbol(
          name: name,
          kind: Constant::SymbolKind::METHOD,
          range_location: new_name_node.location,
          selection_range_location: new_name_node.value_loc, #: as !nil
        )
      end

      private

      #: (name: String, kind: Integer, range_location: Prism::Location, selection_range_location: Prism::Location) -> Interface::DocumentSymbol
      def create_document_symbol(name:, kind:, range_location:, selection_range_location:)
        name = "<blank>" if name.strip.empty?
        symbol = Interface::DocumentSymbol.new(
          name: name,
          kind: kind,
          range: range_from_location(range_location),
          selection_range: range_from_location(selection_range_location),
          children: [],
        )

        @response_builder.last.children << symbol

        symbol
      end

      #: (Prism::CallNode node) -> void
      def handle_attr_accessor(node)
        receiver = node.receiver
        return if receiver && !receiver.is_a?(Prism::SelfNode)

        arguments = node.arguments
        return unless arguments

        arguments.arguments.each do |argument|
          if argument.is_a?(Prism::SymbolNode)
            name = argument.value
            next unless name

            create_document_symbol(
              name: name,
              kind: Constant::SymbolKind::FIELD,
              range_location: argument.location,
              selection_range_location: argument.value_loc, #: as !nil
            )
          elsif argument.is_a?(Prism::StringNode)
            name = argument.content
            next if name.empty?

            create_document_symbol(
              name: name,
              kind: Constant::SymbolKind::FIELD,
              range_location: argument.location,
              selection_range_location: argument.content_loc,
            )
          end
        end
      end

      #: (Prism::CallNode node) -> void
      def handle_alias_method(node)
        receiver = node.receiver
        return if receiver && !receiver.is_a?(Prism::SelfNode)

        arguments = node.arguments
        return unless arguments

        new_name_argument = arguments.arguments.first

        if new_name_argument.is_a?(Prism::SymbolNode)
          name = new_name_argument.value
          return unless name

          create_document_symbol(
            name: name,
            kind: Constant::SymbolKind::METHOD,
            range_location: new_name_argument.location,
            selection_range_location: new_name_argument.value_loc, #: as !nil
          )
        elsif new_name_argument.is_a?(Prism::StringNode)
          name = new_name_argument.content
          return if name.empty?

          create_document_symbol(
            name: name,
            kind: Constant::SymbolKind::METHOD,
            range_location: new_name_argument.location,
            selection_range_location: new_name_argument.content_loc,
          )
        end
      end

      #: (Prism::CallNode node) -> void
      def handle_rake_namespace(node)
        return unless rake?
        return if node.receiver

        arguments = node.arguments
        return unless arguments

        name_argument = arguments.arguments.first
        return unless name_argument

        name = case name_argument
        when Prism::StringNode then name_argument.content
        when Prism::SymbolNode then name_argument.value
        end

        return if name.nil? || name.empty?

        @response_builder << create_document_symbol(
          name: name,
          kind: Constant::SymbolKind::MODULE,
          range_location: name_argument.location,
          selection_range_location: name_argument.location,
        )
      end

      #: (Prism::CallNode node) -> void
      def handle_rake_task(node)
        return unless rake?
        return if node.receiver

        arguments = node.arguments
        return unless arguments

        name_argument = arguments.arguments.first
        return unless name_argument

        name = case name_argument
        when Prism::StringNode then name_argument.content
        when Prism::SymbolNode then name_argument.value
        when Prism::KeywordHashNode
          first_element = name_argument.elements.first
          if first_element.is_a?(Prism::AssocNode)
            key = first_element.key
            case key
            when Prism::StringNode then key.content
            when Prism::SymbolNode then key.value
            end
          end
        end

        return if name.nil? || name.empty?

        create_document_symbol(
          name: name,
          kind: Constant::SymbolKind::METHOD,
          range_location: name_argument.location,
          selection_range_location: name_argument.location,
        )
      end

      #: -> bool
      def rake?
        if (path = @uri.to_standardized_path)
          path.match?(/(Rakefile|\.rake)$/)
        else
          false
        end
      end
    end
  end
end
