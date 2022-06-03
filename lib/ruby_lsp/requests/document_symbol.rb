# typed: true
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [document
    # symbol](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentSymbol) request
    # informs the editor of all the important symbols, such as classes, variables, and methods, defined in a file. With
    # this information, the editor can populate breadcrumbs, file outline and allow for fuzzy symbol searches.
    #
    # In VS Code, fuzzy symbol search can be accessed by opened the command palette and inserting an `@` symbol.
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
      SYMBOL_KIND = {
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
      }.freeze

      ATTR_ACCESSORS = ["attr_reader", "attr_writer", "attr_accessor"].freeze

      class SymbolHierarchyRoot
        attr_reader :children

        def initialize
          @children = []
        end
      end

      def initialize(document)
        super

        @root = SymbolHierarchyRoot.new
        @stack = [@root]
      end

      def run
        visit(@document.tree)
        @root.children
      end

      def visit_class(node)
        symbol = create_document_symbol(
          name: node.constant.constant.value,
          kind: :class,
          range_node: node,
          selection_range_node: node.constant
        )

        @stack << symbol
        visit(node.bodystmt)
        @stack.pop
      end

      def visit_command(node)
        return unless ATTR_ACCESSORS.include?(node.message.value)

        node.arguments.parts.each do |argument|
          next unless argument.is_a?(SyntaxTree::SymbolLiteral)

          create_document_symbol(
            name: argument.value.value,
            kind: :field,
            range_node: argument,
            selection_range_node: argument.value
          )
        end
      end

      def visit_const_path_field(node)
        create_document_symbol(
          name: node.constant.value,
          kind: :constant,
          range_node: node,
          selection_range_node: node.constant
        )
      end

      def visit_def(node)
        name = node.name.value

        symbol = create_document_symbol(
          name: name,
          kind: name == "initialize" ? :constructor : :method,
          range_node: node,
          selection_range_node: node.name
        )

        @stack << symbol
        visit(node.bodystmt)
        @stack.pop
      end

      def visit_def_endless(node)
        name = node.name.value

        symbol = create_document_symbol(
          name: name,
          kind: name == "initialize" ? :constructor : :method,
          range_node: node,
          selection_range_node: node.name
        )

        @stack << symbol
        visit(node.statement)
        @stack.pop
      end

      def visit_defs(node)
        symbol = create_document_symbol(
          name: "self.#{node.name.value}",
          kind: :method,
          range_node: node,
          selection_range_node: node.name
        )

        @stack << symbol
        visit(node.bodystmt)
        @stack.pop
      end

      def visit_module(node)
        symbol = create_document_symbol(
          name: node.constant.constant.value,
          kind: :module,
          range_node: node,
          selection_range_node: node.constant
        )

        @stack << symbol
        visit(node.bodystmt)
        @stack.pop
      end

      def visit_top_const_field(node)
        create_document_symbol(
          name: node.constant.value,
          kind: :constant,
          range_node: node,
          selection_range_node: node.constant
        )
      end

      def visit_var_field(node)
        kind = case node.value
        when SyntaxTree::Const
          :constant
        when SyntaxTree::CVar, SyntaxTree::IVar
          :variable
        else
          return
        end

        create_document_symbol(
          name: node.value.value,
          kind: kind,
          range_node: node,
          selection_range_node: node.value
        )
      end

      private

      def create_document_symbol(name:, kind:, range_node:, selection_range_node:)
        symbol = LanguageServer::Protocol::Interface::DocumentSymbol.new(
          name: name,
          kind: SYMBOL_KIND[kind],
          range: range_from_syntax_tree_node(range_node),
          selection_range: range_from_syntax_tree_node(selection_range_node),
          children: [],
        )

        @stack.last.children << symbol

        symbol
      end
    end
  end
end
