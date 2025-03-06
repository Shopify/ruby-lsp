# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class DocumentSymbol < ResponseBuilder
      ResponseType = type_member { { fixed: T::Array[Interface::DocumentSymbol] } }

      class SymbolHierarchyRoot
        #: Array[Interface::DocumentSymbol]
        attr_reader :children

        #: -> void
        def initialize
          @children = T.let([], T::Array[Interface::DocumentSymbol])
        end
      end

      #: -> void
      def initialize
        super
        @stack = T.let(
          [SymbolHierarchyRoot.new],
          T::Array[T.any(SymbolHierarchyRoot, Interface::DocumentSymbol)],
        )
      end

      #: (Interface::DocumentSymbol symbol) -> void
      def push(symbol)
        @stack << symbol
      end

      alias_method(:<<, :push)

      #: -> Interface::DocumentSymbol?
      def pop
        if @stack.size > 1
          T.cast(@stack.pop, Interface::DocumentSymbol)
        end
      end

      #: -> (SymbolHierarchyRoot | Interface::DocumentSymbol)
      def last
        T.must(@stack.last)
      end

      # @override
      #: -> Array[Interface::DocumentSymbol]
      def response
        T.must(@stack.first).children
      end
    end
  end
end
