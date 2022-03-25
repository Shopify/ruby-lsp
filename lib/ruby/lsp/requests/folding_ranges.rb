# frozen_string_literal: true

module Ruby
  module Lsp
    module Requests
      class FoldingRanges < Visitor
        def self.run(parsed_tree)
          new(parsed_tree).run
        end

        def initialize(parsed_tree)
          @parsed_tree = parsed_tree
          @ranges = []

          super()
        end

        def run
          visit(@parsed_tree.tree)
          @ranges
        end

        def visit_def(node)
          location = node.location

          @ranges << LanguageServer::Protocol::Interface::FoldingRange.new(
            start_line: location.start_line - 1,
            end_line: location.end_line - 1,
            kind: "region"
          )
        end
      end
    end
  end
end
