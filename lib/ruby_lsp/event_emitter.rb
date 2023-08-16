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
  class EventEmitter < YARP::Visitor
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
    sig { params(node: T.nilable(YARP::Node)).void }
    def emit_for_target(node)
      case node
      when YARP::CallNode
        @listeners[:on_call]&.each { |l| T.unsafe(l).on_call(node) }
      when YARP::ConstantPathNode
        @listeners[:on_constant_path_node]&.each { |l| T.unsafe(l).on_constant_path_node(node) }
      when YARP::StringNode
        @listeners[:on_string_node]&.each { |l| T.unsafe(l).on_string_node(node) }
      end
    end

    # Visit dispatchers are below. Notice that for nodes that create a new scope (e.g.: classes, modules, method defs)
    # we need both an `on_*` and `after_*` event. This is because some requests must know when we exit the scope
    sig { override.params(node: T.nilable(YARP::Node)).void }
    def visit(node)
      @listeners[:on_node]&.each { |l| T.unsafe(l).on_node(node) }
      super
    end

    sig { override.params(node: YARP::ClassNode).void }
    def visit_class_node(node)
      @listeners[:on_class]&.each { |l| T.unsafe(l).on_class(node) }
      super
      @listeners[:after_class]&.each { |l| T.unsafe(l).after_class(node) }
    end

    sig { override.params(node: YARP::ModuleNode).void }
    def visit_module_node(node)
      @listeners[:on_module]&.each { |l| T.unsafe(l).on_module(node) }
      super
      @listeners[:after_module]&.each { |l| T.unsafe(l).after_module(node) }
    end

    sig { override.params(node: YARP::CallNode).void }
    def visit_call_node(node)
      @listeners[:on_call]&.each { |l| T.unsafe(l).on_call(node) }
      super
      @listeners[:after_call]&.each { |l| T.unsafe(l).after_call(node) }
    end

    sig { override.params(node: YARP::ConstantPathWriteNode).void }
    def visit_constant_path_write_node(node)
      @listeners[:on_constant_path_write]&.each { |l| T.unsafe(l).on_constant_path_write(node) }
      super
    end

    sig { override.params(node: YARP::ConstantWriteNode).void }
    def visit_constant_write_node(node)
      @listeners[:on_constant_write]&.each { |l| T.unsafe(l).on_constant_write(node) }
      super
    end

    sig { override.params(node: YARP::InstanceVariableWriteNode).void }
    def visit_instance_variable_write_node(node)
      @listeners[:on_instance_variable_write]&.each { |l| T.unsafe(l).on_instance_variable_write(node) }
      super
    end

    sig { override.params(node: YARP::ClassVariableWriteNode).void }
    def visit_class_variable_write_node(node)
      @listeners[:on_class_variable_write]&.each { |l| T.unsafe(l).on_class_variable_write(node) }
      super
    end

    sig { override.params(node: YARP::DefNode).void }
    def visit_def_node(node)
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

    sig { override.params(node: YARP::RescueNode).void }
    def visit_rescue_node(node)
      @listeners[:on_rescue]&.each { |l| T.unsafe(l).on_rescue(node) }
      super
    end

    sig { override.params(node: SyntaxTree::Kw).void }
    def visit_kw(node)
      @listeners[:on_kw]&.each { |l| T.unsafe(l).on_kw(node) }
      super
    end

    sig { override.params(node: SyntaxTree::Params).void }
    def visit_params(node)
      @listeners[:on_params]&.each { |l| T.unsafe(l).on_params(node) }
      super
    end

    sig { override.params(node: SyntaxTree::Field).void }
    def visit_field(node)
      @listeners[:on_field]&.each { |l| T.unsafe(l).on_field(node) }
      super
    end

    sig { override.params(node: SyntaxTree::VarRef).void }
    def visit_var_ref(node)
      @listeners[:on_var_ref]&.each { |l| T.unsafe(l).on_var_ref(node) }
      super
    end

    sig { override.params(node: SyntaxTree::BlockVar).void }
    def visit_block_var(node)
      @listeners[:on_block_var]&.each { |l| T.unsafe(l).on_block_var(node) }
      super
    end

    sig { override.params(node: SyntaxTree::LambdaVar).void }
    def visit_lambda_var(node)
      @listeners[:on_lambda_var]&.each { |l| T.unsafe(l).on_lambda_var(node) }
      super
    end

    sig { override.params(node: SyntaxTree::Binary).void }
    def visit_binary(node)
      super
      @listeners[:after_binary]&.each { |l| T.unsafe(l).after_binary(node) }
    end

    sig { override.params(node: SyntaxTree::Const).void }
    def visit_const(node)
      @listeners[:on_const]&.each { |l| T.unsafe(l).on_const(node) }
      super
    end
  end
end
