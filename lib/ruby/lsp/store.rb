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
        item = @state[uri]
        return item unless item.nil?

        self[uri] = File.binread(CGI.unescape(URI.parse(uri).path))
        @state[uri]
      end

      def []=(uri, content)
        @state[uri] = Item.new(content)
      rescue SyntaxTree::ParseError
        # Do not update the store if there are syntax errors
      end

      def clear
        @state.clear
      end

      def delete(uri)
        @state.delete(uri)
      end

      class Item
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
