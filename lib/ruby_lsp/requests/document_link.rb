# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/document_link"

module RubyLsp
  module Requests
    # The [document link](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentLink)
    # makes `# source://PATH_TO_FILE#line` comments in a Ruby/RBI file clickable if the file exists.
    # When the user clicks the link, it'll open that location.
    class DocumentLink < Request
      extend T::Sig

      class << self
        extend T::Sig

        sig { returns(Interface::DocumentLinkOptions) }
        def provider
          Interface::DocumentLinkOptions.new(resolve_provider: false)
        end
      end

      sig do
        params(
          uri: URI::Generic,
          comments: T::Array[Prism::Comment],
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(uri, comments, dispatcher)
        super()
        @response_builder = T.let(
          ResponseBuilders::CollectionResponseBuilder[Interface::DocumentLink].new,
          ResponseBuilders::CollectionResponseBuilder[Interface::DocumentLink],
        )
        Listeners::DocumentLink.new(@response_builder, uri, comments, dispatcher)
      end

      sig { override.returns(T::Array[Interface::DocumentLink]) }
      def perform
        @response_builder.response
      end
    end
  end
end
