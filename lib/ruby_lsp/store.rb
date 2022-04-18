# frozen_string_literal: true

require "cgi"
require "uri"
require "ruby_lsp/document"

module RubyLsp
  class Store
    def initialize
      @state = {}
    end

    def get(uri)
      document = @state[uri]
      return document unless document.nil?

      set(uri, File.binread(CGI.unescape(URI.parse(uri).path)))
      @state[uri]
    end

    def set(uri, content)
      @state[uri] = Document.new(content)
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
  end
end
