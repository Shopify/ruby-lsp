# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class ReferenceFinder
    extend T::Sig

    class Target
      extend T::Helpers

      abstract!
    end

    class ConstTarget < Target
      extend T::Sig

      sig { returns(String) }
      attr_reader :fully_qualified_name

      sig { params(fully_qualified_name: String).void }
      def initialize(fully_qualified_name)
        super()
        @fully_qualified_name = fully_qualified_name
      end
    end

    class MethodTarget < Target
      extend T::Sig

      sig { returns(String) }
      attr_reader :method_name

      sig { params(method_name: String).void }
      def initialize(method_name)
        super()
        @method_name = method_name
      end
    end

    class Reference
      extend T::Sig

      sig { returns(String) }
      attr_reader :name

      sig { returns(Prism::Location) }
      attr_reader :location

      sig { returns(T::Boolean) }
      attr_reader :declaration

      sig { params(name: String, location: Prism::Location, declaration: T::Boolean).void }
      def initialize(name, location, declaration:)
        @name = name
        @location = location
        @declaration = declaration
      end
    end

    sig do
      params(
        target: Target,
        index: RubyIndexer::Index,
        dispatcher: Prism::Dispatcher,
        include_declarations: T::Boolean,
      ).void
    end
    def initialize(target, index, dispatcher, include_declarations: true)
      @target = target
      @index = index
      @include_declarations = include_declarations
      @stack = T.let([], T::Array[String])
      @references = T.let([], T::Array[Reference])

      dispatcher.register(
        self,
        :on_class_node_enter,
        :on_class_node_leave,
        :on_module_node_enter,
        :on_module_node_leave,
        :on_singleton_class_node_enter,
        :on_singleton_class_node_leave,
        :on_def_node_enter,
        :on_def_node_leave,
        :on_multi_write_node_enter,
        :on_constant_path_write_node_enter,
        :on_constant_path_or_write_node_enter,
        :on_constant_path_operator_write_node_enter,
        :on_constant_path_and_write_node_enter,
        :on_constant_or_write_node_enter,
        :on_constant_path_node_enter,
        :on_constant_read_node_enter,
        :on_constant_write_node_enter,
        :on_constant_or_write_node_enter,
        :on_constant_and_write_node_enter,
        :on_constant_operator_write_node_enter,
        :on_call_node_enter,
      )
    end

    sig { returns(T::Array[Reference]) }
    def references
      return @references if @include_declarations

      @references.reject(&:declaration)
    end

    sig { params(node: Prism::ClassNode).void }
    def on_class_node_enter(node)
      constant_path = node.constant_path
      name = constant_path.slice
      nesting = actual_nesting(name)

      if @target.is_a?(ConstTarget) && nesting.join("::") == @target.fully_qualified_name
        @references << Reference.new(name, constant_path.location, declaration: true)
      end

      @stack << name
    end

    sig { params(node: Prism::ClassNode).void }
    def on_class_node_leave(node)
      @stack.pop
    end

    sig { params(node: Prism::ModuleNode).void }
    def on_module_node_enter(node)
      constant_path = node.constant_path
      name = constant_path.slice
      nesting = actual_nesting(name)

      if @target.is_a?(ConstTarget) && nesting.join("::") == @target.fully_qualified_name
        @references << Reference.new(name, constant_path.location, declaration: true)
      end

      @stack << name
    end

    sig { params(node: Prism::ModuleNode).void }
    def on_module_node_leave(node)
      @stack.pop
    end

    sig { params(node: Prism::SingletonClassNode).void }
    def on_singleton_class_node_enter(node)
      expression = node.expression
      return unless expression.is_a?(Prism::SelfNode)

      @stack << "<Class:#{@stack.last}>"
    end

    sig { params(node: Prism::SingletonClassNode).void }
    def on_singleton_class_node_leave(node)
      @stack.pop
    end

    sig { params(node: Prism::ConstantPathNode).void }
    def on_constant_path_node_enter(node)
      name = constant_name(node)
      return unless name

      collect_constant_references(name, node.location)
    end

    sig { params(node: Prism::ConstantReadNode).void }
    def on_constant_read_node_enter(node)
      name = constant_name(node)
      return unless name

      collect_constant_references(name, node.location)
    end

    sig { params(node: Prism::MultiWriteNode).void }
    def on_multi_write_node_enter(node)
      [*node.lefts, *node.rest, *node.rights].each do |target|
        case target
        when Prism::ConstantTargetNode, Prism::ConstantPathTargetNode
          collect_constant_references(target.name.to_s, target.location)
        end
      end
    end

    sig { params(node: Prism::ConstantPathWriteNode).void }
    def on_constant_path_write_node_enter(node)
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = constant_name(target)
      return unless name

      collect_constant_references(name, target.location)
    end

    sig { params(node: Prism::ConstantPathOrWriteNode).void }
    def on_constant_path_or_write_node_enter(node)
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = constant_name(target)
      return unless name

      collect_constant_references(name, target.location)
    end

    sig { params(node: Prism::ConstantPathOperatorWriteNode).void }
    def on_constant_path_operator_write_node_enter(node)
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = constant_name(target)
      return unless name

      collect_constant_references(name, target.location)
    end

    sig { params(node: Prism::ConstantPathAndWriteNode).void }
    def on_constant_path_and_write_node_enter(node)
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = constant_name(target)
      return unless name

      collect_constant_references(name, target.location)
    end

    sig { params(node: Prism::ConstantWriteNode).void }
    def on_constant_write_node_enter(node)
      collect_constant_references(node.name.to_s, node.name_loc)
    end

    sig { params(node: Prism::ConstantOrWriteNode).void }
    def on_constant_or_write_node_enter(node)
      collect_constant_references(node.name.to_s, node.name_loc)
    end

    sig { params(node: Prism::ConstantAndWriteNode).void }
    def on_constant_and_write_node_enter(node)
      collect_constant_references(node.name.to_s, node.name_loc)
    end

    sig { params(node: Prism::ConstantOperatorWriteNode).void }
    def on_constant_operator_write_node_enter(node)
      collect_constant_references(node.name.to_s, node.name_loc)
    end

    sig { params(node: Prism::DefNode).void }
    def on_def_node_enter(node)
      if @target.is_a?(MethodTarget) && (name = node.name.to_s) == @target.method_name
        @references << Reference.new(name, node.name_loc, declaration: true)
      end

      if node.receiver.is_a?(Prism::SelfNode)
        @stack << "<Class:#{@stack.last}>"
      end
    end

    sig { params(node: Prism::DefNode).void }
    def on_def_node_leave(node)
      if node.receiver.is_a?(Prism::SelfNode)
        @stack.pop
      end
    end

    sig { params(node: Prism::CallNode).void }
    def on_call_node_enter(node)
      if @target.is_a?(MethodTarget) && (name = node.name.to_s) == @target.method_name
        @references << Reference.new(name, T.must(node.message_loc), declaration: false)
      end
    end

    private

    sig { params(name: String).returns(T::Array[String]) }
    def actual_nesting(name)
      nesting = @stack + [name]
      corrected_nesting = []

      nesting.reverse_each do |name|
        corrected_nesting.prepend(name.delete_prefix("::"))

        break if name.start_with?("::")
      end

      corrected_nesting
    end

    sig { params(name: String, location: Prism::Location).void }
    def collect_constant_references(name, location)
      return unless @target.is_a?(ConstTarget)

      entries = @index.resolve(name, @stack)
      return unless entries

      previous_reference = @references.last

      entries.each do |entry|
        next unless entry.name == @target.fully_qualified_name

        # When processing a class/module declaration, we eagerly handle the constant reference. To avoid duplicates,
        # when we find the constant node defining the namespace, then we have to check if it wasn't already added
        next if previous_reference&.location == location

        @references << Reference.new(name, location, declaration: false)
      end
    end

    sig do
      params(
        node: T.any(
          Prism::ConstantPathNode,
          Prism::ConstantReadNode,
          Prism::ConstantPathTargetNode,
        ),
      ).returns(T.nilable(String))
    end
    def constant_name(node)
      node.full_name
    rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError,
           Prism::ConstantPathNode::MissingNodesInConstantPathError
      nil
    end
  end
end
