# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [selection ranges](https://microsoft.github.io/language-server-protocol/specification#textDocument_selectionRange)
    # request informs the editor of ranges that the user may want to select based on the location(s)
    # of their cursor(s).
    #
    # Trigger this request with: Ctrl + Shift + -> or Ctrl + Shift + <-
    #
    # Note that if using VSCode Neovim, you will need to be in Insert mode for this to work correctly.
    class SelectionRanges < Request
      include Support::Common

      #: ((RubyDocument | ERBDocument) document) -> void
      def initialize(document)
        super()
        @document = document
        @ranges = [] #: Array[Support::SelectionRange]
        @stack = [] #: Array[Support::SelectionRange]
      end

      # @override
      #: -> (Array[Support::SelectionRange] & Object)
      def perform
        # [node, parent]
        queue = [[@document.ast, nil]]

        until queue.empty?
          node, parent = queue.shift
          next unless node

          range = Support::SelectionRange.new(range: range_from_location(node.location), parent: parent)
          queue.unshift(*node.child_nodes.map { |child| [child, range] })
          @ranges.unshift(range)
        end

        @ranges
      end
    end
  end
end
