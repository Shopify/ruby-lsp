# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class DocumentSymbol < ResponseBuilder
      extend T::Sig

      ResponseType = type_member { { fixed: T::Array[Interface::DocumentSymbol] } }

      class SymbolHierarchyRoot
        extend T::Sig

        sig { returns(T::Array[Interface::DocumentSymbol]) }
        attr_reader :children

        sig { void }
        def initialize
          @children = T.let([], T::Array[Interface::DocumentSymbol])
        end
      end

      sig { void }
      def initialize
        super
        @stack = T.let(
          [SymbolHierarchyRoot.new],
          T::Array[T.any(SymbolHierarchyRoot, Interface::DocumentSymbol)],
        )
      end

      sig { params(symbol: Interface::DocumentSymbol).void }
      def push(symbol)
        @stack << symbol
      end

      alias_method(:<<, :push)

      sig { returns(T.nilable(Interface::DocumentSymbol)) }
      def pop
        if @stack.size > 1
          T.cast(@stack.pop, Interface::DocumentSymbol)
        end
      end

      sig { returns(T.any(SymbolHierarchyRoot, Interface::DocumentSymbol)) }
      def last
        T.must(@stack.last)
      end

      sig { override.returns(T::Array[Interface::DocumentSymbol]) }
      def response
        T.must(@stack.first).children
      end
    end
  end
end
