# frozen_string_literal: true

module Ruby
  module Lsp
    module Requests
      class FoldingRanges
        def self.run(source)
          new(source).run
        end

        def initialize(source)
          @parser = SyntaxTree.new(source)
          @queue = [@parser.parse]
          @ranges = []
        end

        def run
          until @queue.empty?
            node = @queue.shift

            case node
            when SyntaxTree::Def
              @ranges << CodeRange.new(node.location, "region")
            else
              @queue.unshift(*node.child_nodes.compact)
            end
          end

          @ranges
        end

        class CodeRange
          KINDS = ["comment", "imports", "region"].freeze

          def initialize(location, kind)
            raise ArgumentError, "Invalid folding range kind: #{kind}" unless KINDS.include?(kind)

            @start_line = location.start_line - 1
            @end_line = location.end_line - 1
            @kind = kind
          end

          def to_json(*)
            {
              startLine: @start_line,
              endLine: @end_line,
              kind: @kind,
            }.to_json
          end
        end
      end
    end
  end
end
