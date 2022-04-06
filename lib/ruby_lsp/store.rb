# frozen_string_literal: true

require "cgi"
require "uri"

module RubyLsp
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
    rescue SyntaxTree::Parser::ParseError
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
        @parser = SyntaxTree::Parser.new(source)
        @tree = @parser.parse
        @cache = {}
      end

      def ==(other)
        @source == other.source
      end

      def cache_fetch(request_class)
        cached = @cache[request_class]
        return cached unless cached.nil?

        result = yield
        @cache[request_class] = result
        result
      end
    end
  end
end
