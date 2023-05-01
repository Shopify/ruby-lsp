# typed: strict
# frozen_string_literal: true

module RubyLsp
  # EventEmitter is an intermediary between our requests and Syntax Tree visitors. It's used to visit the document's AST
  # and emit events that the requests can listen to for providing functionality. Usages:
  #
  # - For positional requests, locate the target node and use `emit_for_target` to fire events for each listener
  # - For nonpositional requests, use `visit` to go through the AST, which will fire events for each listener as nodes
  # are found
  #
  # # Example
  #
  # ```ruby
  # target_node = document.locate_node(position)
  # listener = Requests::Hover.new
  # EventEmitter.new(listener).emit_for_target(target_node)
  # listener.response
  # ```
  class EventEmitter < SyntaxTree::Visitor
    extend T::Sig

    sig { params(listeners: Listener[T.untyped]).void }
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
        @listeners.each { |l| T.unsafe(l).on_command(node) if l.registered_for_event?(:on_command) }
      when SyntaxTree::CallNode
        @listeners.each { |l| T.unsafe(l).on_call(node) if l.registered_for_event?(:on_call) }
      when SyntaxTree::ConstPathRef
        @listeners.each { |l| T.unsafe(l).on_const_path_ref(node) if l.registered_for_event?(:on_const_path_ref) }
      when SyntaxTree::Const
        @listeners.each { |l| T.unsafe(l).on_const(node) if l.registered_for_event?(:on_const) }
      end
    end

    # Visit dispatchers are below. Notice that for nodes that create a new scope (e.g.: classes, modules, method defs)
    # we need both an `on_*` and `after_*` event. This is because some requests must know when we exit the scope
    sig { override.params(node: SyntaxTree::ClassDeclaration).void }
    def visit_class(node)
      @listeners.each { |l| T.unsafe(l).on_class(node) if l.registered_for_event?(:on_class) }
      super
      @listeners.each { |l| T.unsafe(l).after_class(node) if l.registered_for_event?(:after_class) }
    end

    sig { override.params(node: SyntaxTree::ModuleDeclaration).void }
    def visit_module(node)
      @listeners.each { |l| T.unsafe(l).on_module(node) if l.registered_for_event?(:on_module) }
      super
      @listeners.each { |l| T.unsafe(l).after_module(node) if l.registered_for_event?(:after_module) }
    end

    sig { override.params(node: SyntaxTree::Command).void }
    def visit_command(node)
      @listeners.each { |l| T.unsafe(l).on_command(node) if l.registered_for_event?(:on_command) }
      super
    end

    sig { override.params(node: SyntaxTree::ConstPathField).void }
    def visit_const_path_field(node)
      @listeners.each { |l| T.unsafe(l).on_const_path_field(node) if l.registered_for_event?(:on_const_path_field) }
      super
    end

    sig { override.params(node: SyntaxTree::TopConstField).void }
    def visit_top_const_field(node)
      @listeners.each { |l| T.unsafe(l).on_top_const_field(node) if l.registered_for_event?(:on_top_const_field) }
      super
    end

    sig { override.params(node: SyntaxTree::DefNode).void }
    def visit_def(node)
      @listeners.each { |l| T.unsafe(l).on_def(node) if l.registered_for_event?(:on_def) }
      super
      @listeners.each { |l| T.unsafe(l).after_def(node) if l.registered_for_event?(:after_def) }
    end

    sig { override.params(node: SyntaxTree::VarField).void }
    def visit_var_field(node)
      @listeners.each { |l| T.unsafe(l).on_var_field(node) if l.registered_for_event?(:on_var_field) }
      super
    end

    sig { override.params(node: SyntaxTree::Comment).void }
    def visit_comment(node)
      @listeners.each { |l| T.unsafe(l).on_comment(node) if l.registered_for_event?(:on_comment) }
      super
    end
  end
end
