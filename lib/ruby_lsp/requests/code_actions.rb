# frozen_string_literal: true

module RubyLsp
  module Requests
    class CodeActions
      def self.run(uri, parsed_tree, range)
        new(uri, parsed_tree, range).run
      end

      def initialize(uri, parsed_tree, range)
        @parsed_tree = parsed_tree
        @uri = uri
        @range = range
      end

      def run
        diagnostics = Diagnostics.run(@uri, @parsed_tree)
        corrections = diagnostics.select { |diagnostic| diagnostic.correctable? && diagnostic.in_range?(@range) }
        return if corrections.empty?

        corrections.map!(&:to_lsp_code_action)
      end
    end
  end
end
