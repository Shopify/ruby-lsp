# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class TestCollection < ResponseBuilder
      extend T::Generic

      ResponseType = type_member { { fixed: Requests::Support::TestItem } }

      #: -> void
      def initialize
        super
        @items = {} #: Hash[String, ResponseType]
      end

      #: (ResponseType item) -> void
      def add(item)
        @items[item.id] = item
      end

      #: (String id) -> ResponseType?
      def [](id)
        @items[id]
      end

      # @override
      #: -> Array[ResponseType]
      def response
        @items.values
      end
    end
  end
end
