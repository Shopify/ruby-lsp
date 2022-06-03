# typed: true
# frozen_string_literal: true

module RubyLsp
  module Requests
    # :nodoc:
    class BaseRequest < SyntaxTree::Visitor
      def self.run(document)
        new(document).run
      end

      def initialize(document)
        @document = document

        super()
      end

      def run
        raise NotImplementedError, "#{self.class}#run must be implemented"
      end

      def range_from_syntax_tree_node(node)
        loc = node.location

        LanguageServer::Protocol::Interface::Range.new(
          start: LanguageServer::Protocol::Interface::Position.new(line: loc.start_line - 1,
            character: loc.start_column),
          end: LanguageServer::Protocol::Interface::Position.new(line: loc.end_line - 1, character: loc.end_column),
        )
      end
    end
  end
end
