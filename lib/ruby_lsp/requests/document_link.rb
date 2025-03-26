# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/document_link"

module RubyLsp
  module Requests
    # The [document link](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentLink)
    # makes `# source://PATH_TO_FILE#line` comments in a Ruby/RBI file clickable if the file exists.
    # When the user clicks the link, it'll open that location.
    class DocumentLink < Request
      class << self
        #: -> Interface::DocumentLinkOptions
        def provider
          Interface::DocumentLinkOptions.new(resolve_provider: false)
        end
      end

      #: (URI::Generic uri, Array[Prism::Comment] comments, Prism::Dispatcher dispatcher) -> void
      def initialize(uri, comments, dispatcher)
        super()
        @response_builder = ResponseBuilders::CollectionResponseBuilder[Interface::DocumentLink]
          .new #: ResponseBuilders::CollectionResponseBuilder[Interface::DocumentLink]
        Listeners::DocumentLink.new(@response_builder, uri, comments, dispatcher)
      end

      # @override
      #: -> Array[Interface::DocumentLink]
      def perform
        @response_builder.response
      end
    end
  end
end
