# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    #: [ResponseType < Object]
    class CollectionResponseBuilder < ResponseBuilder
      #: -> void
      def initialize
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
