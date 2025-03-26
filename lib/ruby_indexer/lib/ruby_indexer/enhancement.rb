# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Enhancement
    extend T::Sig
    extend T::Helpers

    abstract!

    @enhancements = [] #: Array[Class[Enhancement]]

    class << self
      extend T::Sig

      #: (Class[Enhancement] child) -> void
      def inherited(child)
        @enhancements << child
        super
      end

      #: (DeclarationListener listener) -> Array[Enhancement]
      def all(listener)
        @enhancements.map { |enhancement| enhancement.new(listener) }
      end

      # Only available for testing purposes
      #: -> void
      def clear
        @enhancements.clear
      end
    end

    #: (DeclarationListener listener) -> void
    def initialize(listener)
      @listener = listener
    end

    # The `on_extend` indexing enhancement is invoked whenever an extend is encountered in the code. It can be used to
    # register for an included callback, similar to what `ActiveSupport::Concern` does in order to auto-extend the
    # `ClassMethods` modules
    # @overridable
    #: (Prism::CallNode node) -> void
    def on_call_node_enter(node); end # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod

    # @overridable
    #: (Prism::CallNode node) -> void
    def on_call_node_leave(node); end # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
  end
end
