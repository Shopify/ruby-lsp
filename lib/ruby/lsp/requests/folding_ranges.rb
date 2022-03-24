# frozen_string_literal: true

module Ruby
  module Lsp
    module Requests
      class FoldingRanges
        def self.run(parsed_tree)
          new(parsed_tree).run
        end

        def initialize(parsed_tree)
          @queue = [parsed_tree.tree]
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
