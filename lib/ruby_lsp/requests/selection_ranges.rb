# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Selection ranges demo](../../selection_ranges.gif)
    #
    # The [selection ranges](https://microsoft.github.io/language-server-protocol/specification#textDocument_selectionRange)
    # request informs the editor of ranges that the user may want to select based on the location(s)
    # of their cursor(s).
    #
    # Trigger this request with: Ctrl + Shift + -> or Ctrl + Shift + <-
    #
    # Note that if using VSCode Neovim, you will need to be in Insert mode for this to work correctly.
    #
    # # Example
    #
    # ```ruby
    # def foo # --> The next selection range encompasses the entire method definition.
    #   puts "Hello, world!" # --> Cursor is on this line
    # end
    # ```
    class SelectionRanges
      extend T::Sig
      include Support::Common
      sig { params(document: Document).void }
      def initialize(document)
        @document = document
        @ranges = T.let([], T::Array[Support::SelectionRange])
        @stack = T.let([], T::Array[Support::SelectionRange])
      end

      sig { returns(T.all(T::Array[Support::SelectionRange], Object)) }
      def run
        # [node, parent]
        queue = [[@document.tree, nil]]

        until queue.empty?
          node, parent = queue.shift
          next unless node

          range = Support::SelectionRange.new(range: range_from_location(node.location), parent: parent)
          T.unsafe(queue).unshift(*node.child_nodes.map { |child| [child, range] })
          @ranges.unshift(range)
        end

        @ranges
      end
    end
  end
end
