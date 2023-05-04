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
  # emitter = EventEmitter.new
  # listener = Requests::Hover.new(emitter, @message_queue)
  # emitter.emit_for_target(target_node)
  # listener.response
  # ```
  class EventEmitter < SyntaxTree::Visitor
    extend T::Sig

    sig { void }
    def initialize
      @listeners = T.let(Hash.new { |h, k| h[k] = [] }, T::Hash[Symbol, T::Array[Listener[T.untyped]]])
      super()
    end

    sig { params(listener: Listener[T.untyped], events: Symbol).void }
    def register(listener, *events)
      events.each { |event| T.must(@listeners[event]) << listener }
    end

    # Emit events for a specific node. This is similar to the regular `visit` method, but avoids going deeper into the
    # tree for performance
    sig { params(node: T.nilable(SyntaxTree::Node)).void }
    def emit_for_target(node)
      case node
      when SyntaxTree::Command
        @listeners[:on_command]&.each { |l| T.unsafe(l).on_command(node) }
      when SyntaxTree::CallNode
        @listeners[:on_call]&.each { |l| T.unsafe(l).on_call(node) }
      when SyntaxTree::TStringContent
        @listeners[:on_tstring_content]&.each { |l| T.unsafe(l).on_tstring_content(node) }
      when SyntaxTree::ConstPathRef
        @listeners[:on_const_path_ref]&.each { |l| T.unsafe(l).on_const_path_ref(node) }
      when SyntaxTree::Const
        @listeners[:on_const]&.each { |l| T.unsafe(l).on_const(node) }
      end
    end

    # Visit dispatchers are below. Notice that for nodes that create a new scope (e.g.: classes, modules, method defs)
    # we need both an `on_*` and `after_*` event. This is because some requests must know when we exit the scope
    sig { override.params(node: SyntaxTree::ClassDeclaration).void }
    def visit_class(node)
      @listeners[:on_class]&.each { |l| T.unsafe(l).on_class(node) }
      super
      @listeners[:after_class]&.each { |l| T.unsafe(l).after_class(node) }
    end

    sig { override.params(node: SyntaxTree::ModuleDeclaration).void }
    def visit_module(node)
      @listeners[:on_module]&.each { |l| T.unsafe(l).on_module(node) }
      super
      @listeners[:after_module]&.each { |l| T.unsafe(l).after_module(node) }
    end

    sig { override.params(node: SyntaxTree::Command).void }
    def visit_command(node)
      @listeners[:on_command]&.each { |l| T.unsafe(l).on_command(node) }
      super
      @listeners[:after_command]&.each { |l| T.unsafe(l).after_command(node) }
    end

    sig { override.params(node: SyntaxTree::CallNode).void }
    def visit_call(node)
      @listeners[:on_call]&.each { |l| T.unsafe(l).on_call(node) }
      super
      @listeners[:after_call]&.each { |l| T.unsafe(l).after_call(node) }
    end

    sig { override.params(node: SyntaxTree::VCall).void }
    def visit_vcall(node)
      @listeners[:on_vcall]&.each { |l| T.unsafe(l).on_vcall(node) }
      super
    end

    sig { override.params(node: SyntaxTree::ConstPathField).void }
    def visit_const_path_field(node)
      @listeners[:on_const_path_field]&.each { |l| T.unsafe(l).on_const_path_field(node) }
      super
    end

    sig { override.params(node: SyntaxTree::TopConstField).void }
    def visit_top_const_field(node)
      @listeners[:on_top_const_field]&.each { |l| T.unsafe(l).on_top_const_field(node) }
      super
    end

    sig { override.params(node: SyntaxTree::DefNode).void }
    def visit_def(node)
      @listeners[:on_def]&.each { |l| T.unsafe(l).on_def(node) }
      super
      @listeners[:after_def]&.each { |l| T.unsafe(l).after_def(node) }
    end

    sig { override.params(node: SyntaxTree::VarField).void }
    def visit_var_field(node)
      @listeners[:on_var_field]&.each { |l| T.unsafe(l).on_var_field(node) }
      super
    end

    sig { override.params(node: SyntaxTree::Comment).void }
    def visit_comment(node)
      @listeners[:on_comment]&.each { |l| T.unsafe(l).on_comment(node) }
      super
    end
  end
end
