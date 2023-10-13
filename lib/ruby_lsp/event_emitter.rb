# typed: strict
# frozen_string_literal: true

module RubyLsp
  # EventEmitter is an intermediary between our requests and Prism visitors. It's used to visit the document's AST
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
  class EventEmitter < Prism::Visitor
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
    sig { params(node: T.nilable(Prism::Node)).void }
    def emit_for_target(node)
      case node
      when Prism::CallNode
        @listeners[:on_call]&.each { |l| T.unsafe(l).on_call(node) }
      when Prism::ConstantPathNode
        @listeners[:on_constant_path]&.each { |l| T.unsafe(l).on_constant_path(node) }
      when Prism::StringNode
        @listeners[:on_string]&.each { |l| T.unsafe(l).on_string(node) }
      when Prism::ClassNode
        @listeners[:on_class]&.each { |l| T.unsafe(l).on_class(node) }
      when Prism::ModuleNode
        @listeners[:on_module]&.each { |l| T.unsafe(l).on_module(node) }
      when Prism::ConstantWriteNode
        @listeners[:on_constant_write]&.each { |l| T.unsafe(l).on_constant_write(node) }
      when Prism::ConstantReadNode
        @listeners[:on_constant_read]&.each { |l| T.unsafe(l).on_constant_read(node) }
      end
    end

    Prism::Visitor.instance_methods.grep(/^visit_.*_node/).each do |method|
      event_name = method.to_s.delete_prefix("visit_").delete_suffix("_node")

      class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
        def #{method}(node)
          @listeners[:on_#{event_name}]&.each { |l| l.on_#{event_name}(node) }
          super
          @listeners[:after_#{event_name}]&.each { |l| l.after_#{event_name}(node) }
        end
      RUBY
    end
  end
end
