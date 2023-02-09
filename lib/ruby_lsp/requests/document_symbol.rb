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
          # TODO: How do I go about "adding" these in as a Document Symbol
          testcase: 27,
          scope: 28,
        }.freeze,
        T::Hash[Symbol, Integer],
      )

      COMMAND_KIND = T.let(
        {
          attr: :field,
          test_case: :testcase,
          top_level: :scope,
        }.freeze,
        T::Hash[Symbol, Symbol],
      )

      ATTR_ACCESSORS = T.let(["attr_reader", "attr_writer", "attr_accessor"].freeze, T::Array[String])
      RSPEC_TOP_LEVEL_COMMANDS = T.let(["describe", "context"].freeze, T::Array[String])
      TEST_COMMANDS = T.let(["test", "it"].freeze, T::Array[String])
      ALLOW_COMMANDS = T.let((ATTR_ACCESSORS + TEST_COMMANDS + RSPEC_TOP_LEVEL_COMMANDS).freeze, T::Array[String])

      class SymbolHierarchyRoot
        extend T::Sig

        sig { returns(T::Array[LanguageServer::Protocol::Interface::DocumentSymbol]) }
        attr_reader :children

        sig { void }
        def initialize
          @children = T.let([], T::Array[LanguageServer::Protocol::Interface::DocumentSymbol])
        end
      end

      sig { params(document: Document).void }
      def initialize(document)
        super

        @root = T.let(SymbolHierarchyRoot.new, SymbolHierarchyRoot)
        @stack = T.let(
          [@root],
          T::Array[T.any(SymbolHierarchyRoot, LanguageServer::Protocol::Interface::DocumentSymbol)],
        )
      end

      sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Interface::DocumentSymbol], Object)) }
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
        return unless ALLOW_COMMANDS.include?(node.message.value)

        command_type = case node.message.value
        when *TEST_COMMANDS
          :test_case
        when *RSPEC_TOP_LEVEL_COMMANDS
          :top_level
        else
          :attr
        end

        # Handle attr_accessors
        if command_type == :attr
          node.arguments.parts.each do |argument|
            next unless argument.is_a?(SyntaxTree::SymbolLiteral)

            create_document_symbol(
              name: argument.value.value,
              kind: T.must(COMMAND_KIND[command_type]),
              range_node: argument,
              selection_range_node: argument.value,
            )
          end
        # Handle test cases
        elsif command_type == :test_case
          argument = node.arguments.parts.first
          create_document_symbol(
            name: argument.parts.first.value,
            kind: T.must(COMMAND_KIND[command_type]),
            range_node: argument,
            selection_range_node: argument.parts.first,
          )
        # Recursively handle rspecs
        elsif command_type == :top_level
          argument = node.arguments.parts.first
          return unless argument.is_a?(SyntaxTree::StringLiteral)

          symbol = create_document_symbol(
            name: argument.parts.first.value,
            kind: T.must(COMMAND_KIND[command_type]),
            range_node: argument,
            selection_range_node: argument.parts.first,
          )
          @stack << symbol
          # visit(node.bodystmt)
          visit(node.block.bodystmt)
          @stack.pop
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
        if node.target&.value&.value == "self"
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
          selection_range_node: node.value,
        )
      end

      private

      sig do
        params(
          name: String,
          kind: Symbol,
          range_node: SyntaxTree::Node,
          selection_range_node: SyntaxTree::Node,
        ).returns(LanguageServer::Protocol::Interface::DocumentSymbol)
      end
      def create_document_symbol(name:, kind:, range_node:, selection_range_node:)
        symbol = LanguageServer::Protocol::Interface::DocumentSymbol.new(
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
