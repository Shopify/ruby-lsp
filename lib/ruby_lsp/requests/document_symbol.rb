# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Document symbol demo](../../misc/document_symbol.gif)
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
    class DocumentSymbol < BaseRequest
      extend T::Sig

      SYMBOL_KIND = T.let(
        {
          file: 1,
          module: 2,
          namespace: 3,
          package: 4,
          class: 5,
          method: 6,
          property: 7,
          field: 8,
          constructor: 9,
          enum: 10,
          interface: 11,
          function: 12,
          variable: 13,
          constant: 14,
          string: 15,
          number: 16,
          boolean: 17,
          array: 18,
          object: 19,
          key: 20,
          null: 21,
          enummember: 22,
          struct: 23,
          event: 24,
          operator: 25,
          typeparameter: 26,
        }.freeze,
        T::Hash[Symbol, Integer],
      )

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

      sig { params(document: Document).void }
      def initialize(document)
        super

        @root = T.let(SymbolHierarchyRoot.new, SymbolHierarchyRoot)
        @stack = T.let(
          [@root],
          T::Array[T.any(SymbolHierarchyRoot, Interface::DocumentSymbol)],
        )
      end

      sig { override.returns(T.all(T::Array[Interface::DocumentSymbol], Object)) }
      def run
        visit(@document.tree) if @document.parsed?
        @root.children
      end

      sig { override.params(node: SyntaxTree::ClassDeclaration).void }
      def visit_class(node)
        symbol = create_document_symbol(
          name: full_constant_name(node.constant),
          kind: :class,
          range_node: node,
          selection_range_node: node.constant,
        )

        @stack << symbol
        visit(node.bodystmt)
        @stack.pop
      end

      sig { override.params(node: SyntaxTree::Command).void }
      def visit_command(node)
        return visit(node.arguments) unless ATTR_ACCESSORS.include?(node.message.value)

        node.arguments.parts.each do |argument|
          next unless argument.is_a?(SyntaxTree::SymbolLiteral)

          create_document_symbol(
            name: argument.value.value,
            kind: :field,
            range_node: argument,
            selection_range_node: argument.value,
          )
        end
      end

      sig { override.params(node: SyntaxTree::ConstPathField).void }
      def visit_const_path_field(node)
        create_document_symbol(
          name: node.constant.value,
          kind: :constant,
          range_node: node,
          selection_range_node: node.constant,
        )
      end

      sig { override.params(node: SyntaxTree::DefNode).void }
      def visit_def(node)
        target = node.target

        if target.is_a?(SyntaxTree::VarRef) && target.value.is_a?(SyntaxTree::Kw) && target.value.value == "self"
          name = "self.#{node.name.value}"
          kind = :method
        else
          name = node.name.value
          kind = name == "initialize" ? :constructor : :method
        end

        symbol = create_document_symbol(
          name: name,
          kind: kind,
          range_node: node,
          selection_range_node: node.name,
        )

        @stack << symbol
        visit(node.bodystmt)
        @stack.pop
      end

      sig { override.params(node: SyntaxTree::ModuleDeclaration).void }
      def visit_module(node)
        symbol = create_document_symbol(
          name: full_constant_name(node.constant),
          kind: :module,
          range_node: node,
          selection_range_node: node.constant,
        )

        @stack << symbol
        visit(node.bodystmt)
        @stack.pop
      end

      sig { override.params(node: SyntaxTree::TopConstField).void }
      def visit_top_const_field(node)
        create_document_symbol(
          name: node.constant.value,
          kind: :constant,
          range_node: node,
          selection_range_node: node.constant,
        )
      end

      sig { override.params(node: SyntaxTree::VarField).void }
      def visit_var_field(node)
        value = node.value
        kind = case value
        when SyntaxTree::Const
          :constant
        when SyntaxTree::CVar, SyntaxTree::IVar
          :variable
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
          kind: Symbol,
          range_node: SyntaxTree::Node,
          selection_range_node: SyntaxTree::Node,
        ).returns(Interface::DocumentSymbol)
      end
      def create_document_symbol(name:, kind:, range_node:, selection_range_node:)
        symbol = Interface::DocumentSymbol.new(
          name: name,
          kind: SYMBOL_KIND[kind],
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
