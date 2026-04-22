# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    #: [ResponseType < Object]
    class CollectionResponseBuilder < ResponseBuilder
      #: (Encoding, Prism::ParseLexResult) -> void
      def initialize(encoding, parse_result)
        super
        @items = [] #: Array[ResponseType]
      end

      #: (ResponseType item) -> void
      def <<(item)
        @items << item
      end

      # @override
      #: -> Array[ResponseType]
      def response
        @items
      end
    end
  end
end
