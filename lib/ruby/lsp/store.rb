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
        @state[uri] || File.binread(CGI.unescape(URI.parse(uri).path))
      end

      def []=(uri, content)
        @state[uri] = content
      end

      def clear
        @state.clear
      end

      def delete(uri)
        @state.delete(uri)
      end
    end
  end
end
