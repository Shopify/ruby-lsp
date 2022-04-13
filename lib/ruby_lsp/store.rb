# frozen_string_literal: true

require "cgi"
require "uri"

module RubyLsp
  class Store
    def initialize
      @state = {}
    end

    def get(uri)
      parsed_tree = @state[uri]
      return parsed_tree unless parsed_tree.nil?

      set(uri, File.binread(CGI.unescape(URI.parse(uri).path)))
      @state[uri]
    end

    def set(uri, content)
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

    def cache_fetch(uri, request_name, &block)
      get(uri).cache_fetch(request_name, &block)
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

      def cache_fetch(request_name)
        cached = @cache[request_name]
        return cached if cached

        result = yield(self)
        @cache[request_name] = result
        result
      end
    end
  end
end
