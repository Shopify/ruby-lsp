# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class TestCollection < ResponseBuilder
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: Requests::Support::TestItem } }

      sig { void }
      def initialize
        super
        @items = T.let({}, T::Hash[String, ResponseType])
      end

      sig { params(item: ResponseType).void }
      def add(item)
        @items[item.id] = item
      end

      sig { params(id: String).returns(T.nilable(ResponseType)) }
      def [](id)
        @items[id]
      end

      sig { override.returns(T::Array[ResponseType]) }
      def response
        @items.values
      end
    end
  end
end
