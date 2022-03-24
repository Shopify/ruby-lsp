# frozen_string_literal: true

require_relative "../visitor"

module RubyLsp
  module Requests
    class DocumentSymbol < Visitor
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

      class SymbolHierarchyRoot
        attr_reader :children

        def initialize
          @children = []
        end
      end

      def self.run(parsed_tree)
        new(parsed_tree).run
      end

      def initialize(parsed_tree)
        super()
        @parsed_tree = parsed_tree
        @root = SymbolHierarchyRoot.new
        @stack = [@root]
      end

      def run
        visit(@parsed_tree.tree)
        @root.children
      end

      private

      # TODO: clean this once SyntaxTree provides the relative positions
      def range_from_syntax_tree_node(node)
        parser = @parsed_tree.parser
        loc = node.location

        start_line = parser.line_counts[loc.start_line - 1]
        start_column = loc.start_char - start_line.start

        end_line = parser.line_counts[loc.end_line - 1]
        end_column = loc.end_char - end_line.start

        LanguageServer::Protocol::Interface::Range.new(
          start: LanguageServer::Protocol::Interface::Position.new(line: loc.start_line - 1, character: start_column),
          end: LanguageServer::Protocol::Interface::Position.new(line: loc.end_line - 1, character: end_column),
        )
      end
    end
  end
end
