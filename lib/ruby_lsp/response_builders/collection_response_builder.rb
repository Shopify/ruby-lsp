# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class CollectionResponseBuilder < ResponseBuilder
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { upper: Object } }

      sig { void }
      def initialize
        super
        @items = T.let([], T::Array[ResponseType])
      end

      sig { params(item: ResponseType).void }
      def <<(item)
        @items << item
      end

      sig { override.returns(T::Array[ResponseType]) }
      def response
        @items
      end
    end
  end
end
