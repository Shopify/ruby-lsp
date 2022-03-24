# frozen_string_literal: true

require "cgi"
require "uri"

module Ruby
  module Lsp
    class Store
      def initialize
        @state = {}
      end

      def [](uri)
        parsed_tree = @state[uri]
        return parsed_tree unless parsed_tree.nil?

        self[uri] = File.binread(CGI.unescape(URI.parse(uri).path))
        @state[uri]
      end

      def []=(uri, content)
        @state[uri] = ParsedTree.new(content)
      rescue SyntaxTree::ParseError
        # Do not update the store if there are syntax errors
      end

      def clear
        @state.clear
      end

      def delete(uri)
        @state.delete(uri)
      end

      class ParsedTree
        attr_reader :tree, :parser, :source

        def initialize(source)
          @source = source
          @parser = SyntaxTree.new(source)
          @tree = @parser.parse
        end

        def ==(other)
          @source == other.source
        end
      end
    end
  end
end
