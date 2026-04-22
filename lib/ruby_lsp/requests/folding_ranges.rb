# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/folding_ranges"

module RubyLsp
  module Requests
    # The [folding ranges](https://microsoft.github.io/language-server-protocol/specification#textDocument_foldingRange)
    # request informs the editor of the ranges where and how code can be folded.
    class FoldingRanges < Request
      class << self
        #: -> TrueClass
        def provider
          true
        end
      end

      #: ((RubyDocument | ERBDocument) document, Prism::Dispatcher dispatcher) -> void
      def initialize(document, dispatcher)
        super()
        @response_builder = ResponseBuilders::CollectionResponseBuilder
          .new(document.encoding, document.parse_result) #: ResponseBuilders::CollectionResponseBuilder[Interface::FoldingRange]
        @listener = Listeners::FoldingRanges.new(@response_builder, document.parse_result.comments, dispatcher) #: Listeners::FoldingRanges
      end

      # @override
      #: -> Array[Interface::FoldingRange]
      def perform
        @listener.finalize_response!
        @response_builder.response
      end
    end
  end
end
