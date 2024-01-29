# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class Completion < ResponseBuilder
      ResponseType = type_member { { fixed: T::Array[Interface::CompletionItem] } }

      extend T::Sig

      sig { void }
      def initialize
        super
        @items = T.let([], ResponseType)
      end

      sig { params(item: Interface::CompletionItem).void }
      def <<(item)
        @items << item
      end

      sig { override.returns(ResponseType) }
      def response
        @items
      end
    end
  end
end
