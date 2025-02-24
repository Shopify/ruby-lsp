# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class TestCollection < ResponseBuilder
      class DuplicateIdError < StandardError; end

      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: Requests::Support::TestItem } }

      #: -> void
      def initialize
        super
        @items = T.let({}, T::Hash[String, ResponseType])
      end

      #: (ResponseType item) -> void
      def add(item)
        raise DuplicateIdError, "TestItem ID is already in use" if @items.key?(item.id)

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
