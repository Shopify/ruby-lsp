# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Document symbol demo](../../document_symbol.gif)
    #
    # The [document
    # symbol](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentSymbol) request
    # informs the editor of all the important symbols, such as classes, variables, and methods, defined in a file. With
    # this information, the editor can populate breadcrumbs, file outline and allow for fuzzy symbol searches.
    #
    # In VS Code, fuzzy symbol search can be accessed by opening the command palette and inserting an `@` symbol.
    #
    # # Example
    #
    # ```ruby
    # class Person # --> document symbol: class
    #   attr_reader :age # --> document symbol: field
    #
    #   def initialize
    #     @age = 0 # --> document symbol: variable
    #   end
    #
    #   def age # --> document symbol: method
    #   end
    # end
    # ```
    class DocumentSymbol < ExtensibleListener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T::Array[Interface::DocumentSymbol] } }

      ATTR_ACCESSORS = T.let(["attr_reader", "attr_writer", "attr_accessor"].freeze, T::Array[String])

      class SymbolHierarchyRoot
        extend T::Sig

        sig { returns(T::Array[Interface::DocumentSymbol]) }
        attr_reader :children

        sig { void }
        def initialize
          @children = T.let([], T::Array[Interface::DocumentSymbol])
        end
      end

      sig { override.returns(T::Array[Interface::DocumentSymbol]) }
      attr_reader :_response

      sig { params(emitter: EventEmitter, message_queue: Thread::Queue).void }
      def initialize(emitter, message_queue)
        @root = T.let(SymbolHierarchyRoot.new, SymbolHierarchyRoot)
        @_response = T.let(@root.children, T::Array[Interface::DocumentSymbol])
        @stack = T.let(
          [@root],
          T::Array[T.any(SymbolHierarchyRoot, Interface::DocumentSymbol)],
        )

        super

        emitter.register(
          self,
          :on_class,
          :after_class,
          :on_call,
          :on_constant_path_write,
          :on_constant_write,
          :on_def,
          :after_def,
          :on_module,
          :after_module,
          :on_instance_variable_write,
          :on_class_variable_write,
        )
      end

      sig { override.params(extension: RubyLsp::Extension).returns(T.nilable(Listener[ResponseType])) }
      def initialize_external_listener(extension)
        extension.create_document_symbol_listener(@emitter, @message_queue)
      end

      # Merges responses from other listeners
      sig { override.params(other: Listener[ResponseType]).returns(T.self_type) }
      def merge_response!(other)
        @_response.concat(other.response)
        self
      end

      sig { params(node: YARP::ClassNode).void }
      def on_class(node)
        @stack << create_document_symbol(
          name: node.constant_path.location.slice,
          kind: Constant::SymbolKind::CLASS,
          range_node: node,
          selection_range_node: node.constant_path,
        )
      end

      sig { params(node: YARP::ClassNode).void }
      def after_class(node)
        @stack.pop
      end

      sig { params(node: YARP::CallNode).void }
      def on_call(node)
        return unless ATTR_ACCESSORS.include?(node.name) && node.receiver.nil?

        arguments = node.arguments
        return unless arguments

        arguments.arguments.each do |argument|
          next unless argument.is_a?(YARP::SymbolNode)

          name = argument.value
          next unless name

          create_document_symbol(
            name: name,
            kind: Constant::SymbolKind::FIELD,
            range_node: argument,
            selection_range_node: argument,
          )
        end
      end

      sig { params(node: YARP::ConstantPathWriteNode).void }
      def on_constant_path_write(node)
        create_document_symbol(
          name: node.target.location.slice,
          kind: Constant::SymbolKind::CONSTANT,
          range_node: node,
          selection_range_node: node.target,
        )
      end

      sig { params(node: YARP::ConstantWriteNode).void }
      def on_constant_write(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::CONSTANT,
          range_node: node,
          selection_range_node: node.name_loc,
        )
      end

      sig { params(node: YARP::DefNode).void }
      def after_def(node)
        @stack.pop
      end

      sig { params(node: YARP::ModuleNode).void }
      def on_module(node)
        @stack << create_document_symbol(
          name: node.constant_path.location.slice,
          kind: Constant::SymbolKind::MODULE,
          range_node: node,
          selection_range_node: node.constant_path,
        )
      end

      sig { params(node: YARP::DefNode).void }
      def on_def(node)
        receiver = node.receiver

        if receiver.is_a?(YARP::SelfNode)
          name = "self.#{node.name}"
          kind = Constant::SymbolKind::METHOD
        else
          name = node.name.to_s
          kind = name == "initialize" ? Constant::SymbolKind::CONSTRUCTOR : Constant::SymbolKind::METHOD
        end

        symbol = create_document_symbol(
          name: name,
          kind: kind,
          range_node: node,
          selection_range_node: node.name_loc,
        )

        @stack << symbol
      end

      sig { params(node: YARP::ModuleNode).void }
      def after_module(node)
        @stack.pop
      end

      sig { params(node: YARP::InstanceVariableWriteNode).void }
      def on_instance_variable_write(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::VARIABLE,
          range_node: node,
          selection_range_node: node.name_loc,
        )
      end

      sig { params(node: YARP::ClassVariableWriteNode).void }
      def on_class_variable_write(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::VARIABLE,
          range_node: node,
          selection_range_node: node.name_loc,
        )
      end

      private

      sig do
        params(
          name: String,
          kind: Integer,
          range_node: YARP::Node,
          selection_range_node: T.any(YARP::Node, YARP::Location),
        ).returns(Interface::DocumentSymbol)
      end
      def create_document_symbol(name:, kind:, range_node:, selection_range_node:)
        selection_range = if selection_range_node.is_a?(YARP::Node)
          range_from_node(selection_range_node)
        else
          range_from_location(selection_range_node)
        end

        symbol = Interface::DocumentSymbol.new(
          name: name,
          kind: kind,
          range: range_from_node(range_node),
          selection_range: selection_range,
          children: [],
        )

        T.must(@stack.last).children << symbol

        symbol
      end
    end
  end
end
