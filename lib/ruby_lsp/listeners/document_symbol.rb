# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class DocumentSymbol
      extend T::Sig
      include Requests::Support::Common

      ATTR_ACCESSORS = T.let([:attr_reader, :attr_writer, :attr_accessor].freeze, T::Array[Symbol])

      sig do
        params(
          response_builder: ResponseBuilders::DocumentSymbol,
          uri: URI::Generic,
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(response_builder, uri, dispatcher)
        @response_builder = response_builder
        @uri = uri

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

      sig { params(node: Prism::ClassNode).void }
      def on_class_node_enter(node)
        @response_builder << create_document_symbol(
          name: node.constant_path.location.slice,
          kind: Constant::SymbolKind::CLASS,
          range_location: node.location,
          selection_range_location: node.constant_path.location,
        )
      end

      sig { params(node: Prism::ClassNode).void }
      def on_class_node_leave(node)
        @response_builder.pop
      end

      sig { params(node: Prism::SingletonClassNode).void }
      def on_singleton_class_node_enter(node)
        expression = node.expression

        @response_builder << create_document_symbol(
          name: "<< #{expression.slice}",
          kind: Constant::SymbolKind::NAMESPACE,
          range_location: node.location,
          selection_range_location: expression.location,
        )
      end

      sig { params(node: Prism::SingletonClassNode).void }
      def on_singleton_class_node_leave(node)
        @response_builder.pop
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_enter(node)
        node_name = node.name
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

      sig { params(node: Prism::CallNode).void }
      def on_call_node_leave(node)
        return unless rake?

        if node.name == :namespace && !node.receiver
          @response_builder.pop
        end
      end

      sig { params(node: Prism::ConstantPathWriteNode).void }
      def on_constant_path_write_node_enter(node)
        create_document_symbol(
          name: node.target.location.slice,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.target.location,
        )
      end

      sig { params(node: Prism::ConstantWriteNode).void }
      def on_constant_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.name_loc,
        )
      end

      sig { params(node: Prism::ConstantPathAndWriteNode).void }
      def on_constant_path_and_write_node_enter(node)
        create_document_symbol(
          name: node.target.location.slice,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.target.location,
        )
      end

      sig { params(node: Prism::ConstantPathOrWriteNode).void }
      def on_constant_path_or_write_node_enter(node)
        create_document_symbol(
          name: node.target.location.slice,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.target.location,
        )
      end

      sig { params(node: Prism::ConstantPathOperatorWriteNode).void }
      def on_constant_path_operator_write_node_enter(node)
        create_document_symbol(
          name: node.target.location.slice,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.target.location,
        )
      end

      sig { params(node: Prism::ConstantOrWriteNode).void }
      def on_constant_or_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.name_loc,
        )
      end

      sig { params(node: Prism::ConstantAndWriteNode).void }
      def on_constant_and_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.name_loc,
        )
      end

      sig { params(node: Prism::ConstantOperatorWriteNode).void }
      def on_constant_operator_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.name_loc,
        )
      end

      sig { params(node: Prism::ConstantTargetNode).void }
      def on_constant_target_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.location,
        )
      end

      sig { params(node: Prism::ConstantPathTargetNode).void }
      def on_constant_path_target_node_enter(node)
        create_document_symbol(
          name: node.slice,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.location,
        )
      end

      sig { params(node: Prism::DefNode).void }
      def on_def_node_leave(node)
        @response_builder.pop
      end

      sig { params(node: Prism::ModuleNode).void }
      def on_module_node_enter(node)
        @response_builder << create_document_symbol(
          name: node.constant_path.location.slice,
          kind: Constant::SymbolKind::MODULE,
          range_location: node.location,
          selection_range_location: node.constant_path.location,
        )
      end

      sig { params(node: Prism::DefNode).void }
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

        symbol = create_document_symbol(
          name: name,
          kind: kind,
          range_location: node.location,
          selection_range_location: node.name_loc,
        )

        @response_builder << symbol
      end

      sig { params(node: Prism::ModuleNode).void }
      def on_module_node_leave(node)
        @response_builder.pop
      end

      sig { params(node: Prism::ClassVariableWriteNode).void }
      def on_class_variable_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::VARIABLE,
          range_location: node.name_loc,
          selection_range_location: node.name_loc,
        )
      end

      sig { params(node: Prism::InstanceVariableWriteNode).void }
      def on_instance_variable_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::FIELD,
          range_location: node.name_loc,
          selection_range_location: node.name_loc,
        )
      end

      sig { params(node: Prism::InstanceVariableTargetNode).void }
      def on_instance_variable_target_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::FIELD,
          range_location: node.location,
          selection_range_location: node.location,
        )
      end

      sig { params(node: Prism::InstanceVariableOperatorWriteNode).void }
      def on_instance_variable_operator_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::FIELD,
          range_location: node.name_loc,
          selection_range_location: node.name_loc,
        )
      end

      sig { params(node: Prism::InstanceVariableOrWriteNode).void }
      def on_instance_variable_or_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::FIELD,
          range_location: node.name_loc,
          selection_range_location: node.name_loc,
        )
      end

      sig { params(node: Prism::InstanceVariableAndWriteNode).void }
      def on_instance_variable_and_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::FIELD,
          range_location: node.name_loc,
          selection_range_location: node.name_loc,
        )
      end

      sig { params(node: Prism::AliasMethodNode).void }
      def on_alias_method_node_enter(node)
        new_name_node = node.new_name
        return unless new_name_node.is_a?(Prism::SymbolNode)

        name = new_name_node.value
        return unless name

        create_document_symbol(
          name: name,
          kind: Constant::SymbolKind::METHOD,
          range_location: new_name_node.location,
          selection_range_location: T.must(new_name_node.value_loc),
        )
      end

      private

      sig do
        params(
          name: String,
          kind: Integer,
          range_location: Prism::Location,
          selection_range_location: Prism::Location,
        ).returns(Interface::DocumentSymbol)
      end
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

      sig { params(node: Prism::CallNode).void }
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
              selection_range_location: T.must(argument.value_loc),
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

      sig { params(node: Prism::CallNode).void }
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
            selection_range_location: T.must(new_name_argument.value_loc),
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

      sig { params(node: Prism::CallNode).void }
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

      sig { params(node: Prism::CallNode).void }
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

      sig { returns(T::Boolean) }
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
