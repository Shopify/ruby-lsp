# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # Show syntax tree is a custom [LSP
    # request](https://microsoft.github.io/language-server-protocol/specification#requestMessage) that displays the AST
    # for the current document or for the current selection in a new tab.
    class ShowSyntaxTree < Request
      #: (RubyDocument document, Hash[Symbol, untyped]? range) -> void
      def initialize(document, range)
        super()
        @document = document
        @range = range
        @tree = document.ast #: Prism::ProgramNode
      end

      # @override
      #: -> String
      def perform
        return ast_for_range if @range

        output_string = +""
        PP.pp(@tree, output_string)
        output_string
      end

      private

      #: -> String
      def ast_for_range
        range = @range #: as !nil
        start_char, end_char = @document.find_index_by_position(range[:start], range[:end])

        queue = @tree.statements.body.dup
        found_nodes = []

        until queue.empty?
          node = queue.shift
          next unless node

          loc = node.location

          # If the node is fully covered by the selection, then we found one of the nodes to be displayed and don't want
          # to continue descending into its children
          if (start_char..end_char).cover?(loc.start_offset..loc.end_offset)
            found_nodes << node
          else
            queue.unshift(*node.child_nodes)
          end
        end

        found_nodes.map do |node|
          output_string = +""
          PP.pp(node, output_string)
          output_string
        end.join("\n")
      end
    end
  end
end
