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
      attr_reader :response

      sig { params(emitter: EventEmitter, message_queue: Thread::Queue).void }
      def initialize(emitter, message_queue)
        @root = T.let(SymbolHierarchyRoot.new, SymbolHierarchyRoot)
        @response = T.let(@root.children, T::Array[Interface::DocumentSymbol])
        @stack = T.let(
          [@root],
          T::Array[T.any(SymbolHierarchyRoot, Interface::DocumentSymbol)],
        )

        super

        emitter.register(
          self,
          :on_class,
          :after_class,
          :on_command,
          :on_const_path_field,
          :on_def,
          :after_def,
          :on_module,
          :after_module,
          :on_top_const_field,
          :on_var_field,
        )
      end

      sig { override.params(extension: RubyLsp::Extension).returns(T.nilable(Listener[ResponseType])) }
      def initialize_external_listener(extension)
        extension.create_document_symbol_listener(@emitter, @message_queue)
      end

      # Merges responses from other listeners
      sig { override.params(other: Listener[ResponseType]).returns(T.self_type) }
      def merge_response!(other)
        @response.concat(other.response)
        self
      end

      sig { params(node: SyntaxTree::ClassDeclaration).void }
      def on_class(node)
        @stack << create_document_symbol(
          name: full_constant_name(node.constant),
          kind: Constant::SymbolKind::CLASS,
          range_node: node,
          selection_range_node: node.constant,
        )
      end

      sig { params(node: SyntaxTree::ClassDeclaration).void }
      def after_class(node)
        @stack.pop
      end

      sig { params(node: SyntaxTree::Command).void }
      def on_command(node)
        return unless ATTR_ACCESSORS.include?(node.message.value)

        node.arguments.parts.each do |argument|
          next unless argument.is_a?(SyntaxTree::SymbolLiteral)

          create_document_symbol(
            name: argument.value.value,
            kind: Constant::SymbolKind::FIELD,
            range_node: argument,
            selection_range_node: argument.value,
          )
        end
      end

      sig { params(node: SyntaxTree::ConstPathField).void }
      def on_const_path_field(node)
        create_document_symbol(
          name: node.constant.value,
          kind: Constant::SymbolKind::CONSTANT,
          range_node: node,
          selection_range_node: node.constant,
        )
      end

      sig { params(node: SyntaxTree::DefNode).void }
      def on_def(node)
        target = node.target

        if target.is_a?(SyntaxTree::VarRef) && target.value.is_a?(SyntaxTree::Kw) && target.value.value == "self"
          name = "self.#{node.name.value}"
          kind = Constant::SymbolKind::METHOD
        else
          name = node.name.value
          kind = name == "initialize" ? Constant::SymbolKind::CONSTRUCTOR : Constant::SymbolKind::METHOD
        end

        symbol = create_document_symbol(
          name: name,
          kind: kind,
          range_node: node,
          selection_range_node: node.name,
        )

        @stack << symbol
      end

      sig { params(node: SyntaxTree::DefNode).void }
      def after_def(node)
        @stack.pop
      end

      sig { params(node: SyntaxTree::ModuleDeclaration).void }
      def on_module(node)
        @stack << create_document_symbol(
          name: full_constant_name(node.constant),
          kind: Constant::SymbolKind::MODULE,
          range_node: node,
          selection_range_node: node.constant,
        )
      end

      sig { params(node: SyntaxTree::ModuleDeclaration).void }
      def after_module(node)
        @stack.pop
      end

      sig { params(node: SyntaxTree::TopConstField).void }
      def on_top_const_field(node)
        create_document_symbol(
          name: node.constant.value,
          kind: Constant::SymbolKind::CONSTANT,
          range_node: node,
          selection_range_node: node.constant,
        )
      end

      sig { params(node: SyntaxTree::VarField).void }
      def on_var_field(node)
        value = node.value
        kind = case value
        when SyntaxTree::Const
          Constant::SymbolKind::CONSTANT
        when SyntaxTree::CVar, SyntaxTree::IVar
          Constant::SymbolKind::VARIABLE
        else
          return
        end

        create_document_symbol(
          name: value.value,
          kind: kind,
          range_node: node,
          selection_range_node: value,
        )
      end

      private

      sig do
        params(
          name: String,
          kind: Integer,
          range_node: SyntaxTree::Node,
          selection_range_node: SyntaxTree::Node,
        ).returns(Interface::DocumentSymbol)
      end
      def create_document_symbol(name:, kind:, range_node:, selection_range_node:)
        symbol = Interface::DocumentSymbol.new(
          name: name,
          kind: kind,
          range: range_from_syntax_tree_node(range_node),
          selection_range: range_from_syntax_tree_node(selection_range_node),
          children: [],
        )

        T.must(@stack.last).children << symbol

        symbol
      end
    end
  end
end
