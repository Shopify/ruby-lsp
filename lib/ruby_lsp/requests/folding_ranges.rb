# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/folding_ranges"

module RubyLsp
  module Requests
    # The [folding ranges](https://microsoft.github.io/language-server-protocol/specification#textDocument_foldingRange)
    # request informs the editor of the ranges where and how code can be folded.
    class FoldingRanges < Request
      extend T::Sig

      class << self
        extend T::Sig

        sig { returns(Interface::FoldingRangeRegistrationOptions) }
        def provider
          Interface::FoldingRangeRegistrationOptions.new(
            document_selector: [
              Interface::DocumentFilter.new(language: "ruby"),
            ],
          )
        end
      end

      sig { params(comments: T::Array[Prism::Comment], dispatcher: Prism::Dispatcher).void }
      def initialize(comments, dispatcher)
        super()
        @response_builder = T.let(
          ResponseBuilders::CollectionResponseBuilder[Interface::FoldingRange].new,
          ResponseBuilders::CollectionResponseBuilder[Interface::FoldingRange],
        )
        @listener = T.let(
          Listeners::FoldingRanges.new(@response_builder, comments, dispatcher),
          Listeners::FoldingRanges,
        )
      end

      sig { override.returns(T::Array[Interface::FoldingRange]) }
      def perform
        @listener.finalize_response!
        @response_builder.response
      end
    end
  end
end
