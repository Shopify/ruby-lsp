# typed: strict
# frozen_string_literal: true

module RubyLsp
  class EventEmitter < SyntaxTree::Visitor
    extend T::Sig

    sig { params(listeners: Listener).void }
    def initialize(*listeners)
      @listeners = listeners

      super()
    end

    # Emit events for a specific node. This is similar to the regular `visit` method, but avoids going deeper into the
    # tree for performance
    sig { params(node: T.nilable(SyntaxTree::Node)).void }
    def emit_for_position(node)
      case node
      when SyntaxTree::Command
        @listeners.each { |listener| listener.on_command(node) }
      when SyntaxTree::CallNode
        @listeners.each { |listener| listener.on_call(node) }
      when SyntaxTree::ConstPathRef
        @listeners.each { |listener| listener.on_const_path_ref(node) }
      end
    end
  end
end
