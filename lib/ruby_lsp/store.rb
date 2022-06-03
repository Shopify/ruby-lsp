# typed: strict
# frozen_string_literal: true

require "cgi"
require "uri"
require "ruby_lsp/document"

module RubyLsp
  class Store
    extend T::Sig

    sig { void }
    def initialize
      @state = T.let({}, T::Hash[String, Document])
    end

    sig { params(uri: String).returns(Document) }
    def get(uri)
      document = @state[uri]
      return document unless document.nil?

      set(uri, File.binread(CGI.unescape(URI.parse(uri).path)))
      T.must(@state[uri])
    end

    sig { params(uri: String, content: String).void }
    def set(uri, content)
      @state[uri] = Document.new(content)
    rescue SyntaxTree::Parser::ParseError
      # Do not update the store if there are syntax errors
    end

    sig { params(uri: String, edits: T::Array[Document::EditShape]).void }
    def push_edits(uri, edits)
      T.must(@state[uri]).push_edits(edits)
    end

    sig { void }
    def clear
      @state.clear
    end

    sig { params(uri: String).void }
    def delete(uri)
      @state.delete(uri)
    end

    sig do
      params(
        uri: String,
        request_name: Symbol,
        block: T.proc.params(document: Document).returns(T.untyped)
      ).returns(T.untyped)
    end
    def cache_fetch(uri, request_name, &block)
      get(uri).cache_fetch(request_name, &block)
    end
  end
end
