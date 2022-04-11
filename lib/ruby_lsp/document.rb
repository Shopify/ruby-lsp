# frozen_string_literal: true

module RubyLsp
  class Document
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
