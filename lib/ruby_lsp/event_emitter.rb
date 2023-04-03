# typed: strict
# frozen_string_literal: true

module RubyLsp
  # EventEmitter is an intermediary between our requests and Syntax Tree visitors. It's used to visit the document's AST
  # and emit events that the requests can listen to for providing functionality. Usages:
  # - For positional requests, locate the target node and use `emit_for_target` to fire events for each listener
  # - For nonpositional requests, use `visit` to go through the AST, which will fire events for each listener as nodes
  # are found
  # = Example
  # ```ruby
  # target_node = document.locate_node(position)
  # listener = Requests::Hover.new
  # EventEmitter.new(listener).emit_for_target(target_node)
  # listener.response
  # ```
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
    def emit_for_target(node)
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
