# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Enhancement
    extend T::Sig
    extend T::Helpers

    abstract!

    @enhancements = T.let([], T::Array[T::Class[Enhancement]])

    class << self
      extend T::Sig

      sig { params(child: T::Class[Enhancement]).void }
      def inherited(child)
        @enhancements << child
        super
      end

      sig { params(listener: DeclarationListener).returns(T::Array[Enhancement]) }
      def all(listener)
        @enhancements.map { |enhancement| enhancement.new(listener) }
      end

      # Only available for testing purposes
      sig { void }
      def clear
        @enhancements.clear
      end
    end

    sig { params(listener: DeclarationListener).void }
    def initialize(listener)
      @listener = listener
    end

    # The `on_extend` indexing enhancement is invoked whenever an extend is encountered in the code. It can be used to
    # register for an included callback, similar to what `ActiveSupport::Concern` does in order to auto-extend the
    # `ClassMethods` modules
    sig { overridable.params(node: Prism::CallNode).void }
    def on_call_node_enter(node); end # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod

    sig { overridable.params(node: Prism::CallNode).void }
    def on_call_node_leave(node); end # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
  end
end
