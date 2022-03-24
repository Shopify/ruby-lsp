# frozen_string_literal: true

module Ruby
  module Lsp
    module Requests
      class FoldingRanges
        def self.run(item)
          new(item).run
        end

        def initialize(item)
          @queue = [item.tree]
          @ranges = []
        end

        def run
          until @queue.empty?
            node = @queue.shift

            case node
            when SyntaxTree::Def
              location = node.location

              @ranges << LanguageServer::Protocol::Interface::FoldingRange.new(
                start_line: location.start_line - 1,
                end_line: location.end_line - 1,
                kind: "region"
              )
            else
              @queue.unshift(*node.child_nodes.compact)
            end
          end

          @ranges
        end
      end
    end
  end
end
