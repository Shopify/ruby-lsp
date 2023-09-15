# typed: strict
# frozen_string_literal: true

module RubyLsp
  # EventEmitter is an intermediary between our requests and YARP visitors. It's used to visit the document's AST
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
        @listeners[:on_constant_path]&.each { |l| T.unsafe(l).on_constant_path(node) }
      when YARP::StringNode
        @listeners[:on_string]&.each { |l| T.unsafe(l).on_string(node) }
      when YARP::ClassNode
        @listeners[:on_class]&.each { |l| T.unsafe(l).on_class(node) }
      when YARP::ModuleNode
        @listeners[:on_module]&.each { |l| T.unsafe(l).on_module(node) }
      when YARP::ConstantWriteNode
        @listeners[:on_constant_write]&.each { |l| T.unsafe(l).on_constant_write(node) }
      when YARP::ConstantReadNode
        @listeners[:on_constant_read]&.each { |l| T.unsafe(l).on_constant_read(node) }
      end
    end

    # Visit dispatchers are below. Notice that for nodes that create a new scope (e.g.: classes, modules, method defs)
    # we need both an `on_*` and `after_*` event. This is because some requests must know when we exit the scope
    sig { override.params(node: T.nilable(YARP::Node)).void }
    def visit(node)
      @listeners[:on_node]&.each { |l| T.unsafe(l).on_node(node) }
      super
    end

    sig { params(nodes: T::Array[T.nilable(YARP::Node)]).void }
    def visit_all(nodes)
      nodes.each { |node| visit(node) }
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

    sig { override.params(node: YARP::BlockNode).void }
    def visit_block_node(node)
      @listeners[:on_block]&.each { |l| T.unsafe(l).on_block(node) }
      super
      @listeners[:after_block]&.each { |l| T.unsafe(l).after_block(node) }
    end

    sig { override.params(node: YARP::SelfNode).void }
    def visit_self_node(node)
      @listeners[:on_self]&.each { |l| T.unsafe(l).on_self(node) }
      super
    end

    sig { override.params(node: YARP::RescueNode).void }
    def visit_rescue_node(node)
      @listeners[:on_rescue]&.each { |l| T.unsafe(l).on_rescue(node) }
      super
    end

    sig { override.params(node: YARP::BlockParameterNode).void }
    def visit_block_parameter_node(node)
      @listeners[:on_block_parameter]&.each { |l| T.unsafe(l).on_block_parameter(node) }
      super
    end

    sig { override.params(node: YARP::KeywordParameterNode).void }
    def visit_keyword_parameter_node(node)
      @listeners[:on_keyword_parameter]&.each { |l| T.unsafe(l).on_keyword_parameter(node) }
      super
    end

    sig { override.params(node: YARP::KeywordRestParameterNode).void }
    def visit_keyword_rest_parameter_node(node)
      @listeners[:on_keyword_rest_parameter]&.each { |l| T.unsafe(l).on_keyword_rest_parameter(node) }
      super
    end

    sig { override.params(node: YARP::OptionalParameterNode).void }
    def visit_optional_parameter_node(node)
      @listeners[:on_optional_parameter]&.each { |l| T.unsafe(l).on_optional_parameter(node) }
      super
    end

    sig { override.params(node: YARP::RequiredParameterNode).void }
    def visit_required_parameter_node(node)
      @listeners[:on_required_parameter]&.each { |l| T.unsafe(l).on_required_parameter(node) }
      super
    end

    sig { override.params(node: YARP::RestParameterNode).void }
    def visit_rest_parameter_node(node)
      @listeners[:on_rest_parameter]&.each { |l| T.unsafe(l).on_rest_parameter(node) }
      super
    end

    sig { override.params(node: YARP::ConstantReadNode).void }
    def visit_constant_read_node(node)
      @listeners[:on_constant_read]&.each { |l| T.unsafe(l).on_constant_read(node) }
      super
    end

    sig { override.params(node: YARP::ConstantPathNode).void }
    def visit_constant_path_node(node)
      @listeners[:on_constant_path]&.each { |l| T.unsafe(l).on_constant_path(node) }
      super
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

    sig { override.params(node: YARP::ConstantAndWriteNode).void }
    def visit_constant_and_write_node(node)
      @listeners[:on_constant_and_write]&.each { |l| T.unsafe(l).on_constant_and_write(node) }
      super
    end

    sig { override.params(node: YARP::ConstantOperatorWriteNode).void }
    def visit_constant_operator_write_node(node)
      @listeners[:on_constant_operator_write]&.each { |l| T.unsafe(l).on_constant_operator_write(node) }
      super
    end

    sig { override.params(node: YARP::ConstantOrWriteNode).void }
    def visit_constant_or_write_node(node)
      @listeners[:on_constant_or_write]&.each { |l| T.unsafe(l).on_constant_or_write(node) }
      super
    end

    sig { override.params(node: YARP::ConstantTargetNode).void }
    def visit_constant_target_node(node)
      @listeners[:on_constant_target]&.each { |l| T.unsafe(l).on_constant_target(node) }
      super
    end

    sig { override.params(node: YARP::LocalVariableWriteNode).void }
    def visit_local_variable_write_node(node)
      @listeners[:on_local_variable_write]&.each { |l| T.unsafe(l).on_local_variable_write(node) }
      super
    end

    sig { override.params(node: YARP::LocalVariableReadNode).void }
    def visit_local_variable_read_node(node)
      @listeners[:on_local_variable_read]&.each { |l| T.unsafe(l).on_local_variable_read(node) }
      super
    end

    sig { override.params(node: YARP::LocalVariableAndWriteNode).void }
    def visit_local_variable_and_write_node(node)
      @listeners[:on_local_variable_and_write]&.each { |l| T.unsafe(l).on_local_variable_and_write(node) }
      super
    end

    sig { override.params(node: YARP::LocalVariableOperatorWriteNode).void }
    def visit_local_variable_operator_write_node(node)
      @listeners[:on_local_variable_operator_write]&.each { |l| T.unsafe(l).on_local_variable_operator_write(node) }
      super
    end

    sig { override.params(node: YARP::LocalVariableOrWriteNode).void }
    def visit_local_variable_or_write_node(node)
      @listeners[:on_local_variable_or_write]&.each { |l| T.unsafe(l).on_local_variable_or_write(node) }
      super
    end

    sig { override.params(node: YARP::LocalVariableTargetNode).void }
    def visit_local_variable_target_node(node)
      @listeners[:on_local_variable_target]&.each { |l| T.unsafe(l).on_local_variable_target(node) }
      super
    end

    sig { override.params(node: YARP::LambdaNode).void }
    def visit_lambda_node(node)
      @listeners[:on_lambda]&.each { |l| T.unsafe(l).on_lambda(node) }
      super
      @listeners[:after_lambda]&.each { |l| T.unsafe(l).after_lambda(node) }
    end
  end
end
