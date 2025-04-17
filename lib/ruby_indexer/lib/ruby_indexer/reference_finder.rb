# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class ReferenceFinder
    class Target
      extend T::Helpers

      abstract!
    end

    class ConstTarget < Target
      #: String
      attr_reader :fully_qualified_name

      #: (String fully_qualified_name) -> void
      def initialize(fully_qualified_name)
        super()
        @fully_qualified_name = fully_qualified_name
      end
    end

    class MethodTarget < Target
      #: String
      attr_reader :method_name

      #: (String method_name) -> void
      def initialize(method_name)
        super()
        @method_name = method_name
      end
    end

    class InstanceVariableTarget < Target
      #: String
      attr_reader :name

      #: (String name) -> void
      def initialize(name)
        super()
        @name = name
      end
    end

    class Reference
      #: String
      attr_reader :name

      #: Prism::Location
      attr_reader :location

      #: bool
      attr_reader :declaration

      #: (String name, Prism::Location location, declaration: bool) -> void
      def initialize(name, location, declaration:)
        @name = name
        @location = location
        @declaration = declaration
      end
    end

    #: (Target target, RubyIndexer::Index index, Prism::Dispatcher dispatcher, URI::Generic uri, ?include_declarations: bool) -> void
    def initialize(target, index, dispatcher, uri, include_declarations: true)
      @target = target
      @index = index
      @uri = uri
      @include_declarations = include_declarations
      @stack = [] #: Array[String]
      @references = [] #: Array[Reference]

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
        :on_instance_variable_read_node_enter,
        :on_instance_variable_write_node_enter,
        :on_instance_variable_and_write_node_enter,
        :on_instance_variable_operator_write_node_enter,
        :on_instance_variable_or_write_node_enter,
        :on_instance_variable_target_node_enter,
        :on_call_node_enter,
      )
    end

    #: -> Array[Reference]
    def references
      return @references if @include_declarations

      @references.reject(&:declaration)
    end

    #: (Prism::ClassNode node) -> void
    def on_class_node_enter(node)
      @stack << node.constant_path.slice
    end

    #: (Prism::ClassNode node) -> void
    def on_class_node_leave(node)
      @stack.pop
    end

    #: (Prism::ModuleNode node) -> void
    def on_module_node_enter(node)
      @stack << node.constant_path.slice
    end

    #: (Prism::ModuleNode node) -> void
    def on_module_node_leave(node)
      @stack.pop
    end

    #: (Prism::SingletonClassNode node) -> void
    def on_singleton_class_node_enter(node)
      expression = node.expression
      return unless expression.is_a?(Prism::SelfNode)

      @stack << "<Class:#{@stack.last}>"
    end

    #: (Prism::SingletonClassNode node) -> void
    def on_singleton_class_node_leave(node)
      @stack.pop
    end

    #: (Prism::ConstantPathNode node) -> void
    def on_constant_path_node_enter(node)
      name = Index.constant_name(node)
      return unless name

      collect_constant_references(name, node.location)
    end

    #: (Prism::ConstantReadNode node) -> void
    def on_constant_read_node_enter(node)
      name = Index.constant_name(node)
      return unless name

      collect_constant_references(name, node.location)
    end

    #: (Prism::MultiWriteNode node) -> void
    def on_multi_write_node_enter(node)
      [*node.lefts, *node.rest, *node.rights].each do |target|
        case target
        when Prism::ConstantTargetNode, Prism::ConstantPathTargetNode
          collect_constant_references(target.name.to_s, target.location)
        end
      end
    end

    #: (Prism::ConstantPathWriteNode node) -> void
    def on_constant_path_write_node_enter(node)
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = Index.constant_name(target)
      return unless name

      collect_constant_references(name, target.location)
    end

    #: (Prism::ConstantPathOrWriteNode node) -> void
    def on_constant_path_or_write_node_enter(node)
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = Index.constant_name(target)
      return unless name

      collect_constant_references(name, target.location)
    end

    #: (Prism::ConstantPathOperatorWriteNode node) -> void
    def on_constant_path_operator_write_node_enter(node)
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = Index.constant_name(target)
      return unless name

      collect_constant_references(name, target.location)
    end

    #: (Prism::ConstantPathAndWriteNode node) -> void
    def on_constant_path_and_write_node_enter(node)
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = Index.constant_name(target)
      return unless name

      collect_constant_references(name, target.location)
    end

    #: (Prism::ConstantWriteNode node) -> void
    def on_constant_write_node_enter(node)
      collect_constant_references(node.name.to_s, node.name_loc)
    end

    #: (Prism::ConstantOrWriteNode node) -> void
    def on_constant_or_write_node_enter(node)
      collect_constant_references(node.name.to_s, node.name_loc)
    end

    #: (Prism::ConstantAndWriteNode node) -> void
    def on_constant_and_write_node_enter(node)
      collect_constant_references(node.name.to_s, node.name_loc)
    end

    #: (Prism::ConstantOperatorWriteNode node) -> void
    def on_constant_operator_write_node_enter(node)
      collect_constant_references(node.name.to_s, node.name_loc)
    end

    #: (Prism::DefNode node) -> void
    def on_def_node_enter(node)
      if @target.is_a?(MethodTarget) && (name = node.name.to_s) == @target.method_name
        @references << Reference.new(name, node.name_loc, declaration: true)
      end

      if node.receiver.is_a?(Prism::SelfNode)
        @stack << "<Class:#{@stack.last}>"
      end
    end

    #: (Prism::DefNode node) -> void
    def on_def_node_leave(node)
      if node.receiver.is_a?(Prism::SelfNode)
        @stack.pop
      end
    end

    #: (Prism::InstanceVariableReadNode node) -> void
    def on_instance_variable_read_node_enter(node)
      collect_instance_variable_references(node.name.to_s, node.location, false)
    end

    #: (Prism::InstanceVariableWriteNode node) -> void
    def on_instance_variable_write_node_enter(node)
      collect_instance_variable_references(node.name.to_s, node.name_loc, true)
    end

    #: (Prism::InstanceVariableAndWriteNode node) -> void
    def on_instance_variable_and_write_node_enter(node)
      collect_instance_variable_references(node.name.to_s, node.name_loc, true)
    end

    #: (Prism::InstanceVariableOperatorWriteNode node) -> void
    def on_instance_variable_operator_write_node_enter(node)
      collect_instance_variable_references(node.name.to_s, node.name_loc, true)
    end

    #: (Prism::InstanceVariableOrWriteNode node) -> void
    def on_instance_variable_or_write_node_enter(node)
      collect_instance_variable_references(node.name.to_s, node.name_loc, true)
    end

    #: (Prism::InstanceVariableTargetNode node) -> void
    def on_instance_variable_target_node_enter(node)
      collect_instance_variable_references(node.name.to_s, node.location, true)
    end

    #: (Prism::CallNode node) -> void
    def on_call_node_enter(node)
      if @target.is_a?(MethodTarget) && (name = node.name.to_s) == @target.method_name
        @references << Reference.new(
          name,
          node.message_loc, #: as !nil
          declaration: false,
        )
      end
    end

    private

    #: (String name, Prism::Location location) -> void
    def collect_constant_references(name, location)
      return unless @target.is_a?(ConstTarget)

      entries = @index.resolve(name, @stack)
      return unless entries

      # Filter down to all constant declarations that match the expected name and type
      matching_entries = entries.select do |e|
        [
          Entry::Namespace,
          Entry::Constant,
          Entry::ConstantAlias,
          Entry::UnresolvedConstantAlias,
        ].any? { |klass| e.is_a?(klass) } &&
          e.name == @target.fully_qualified_name
      end

      return if matching_entries.empty?

      # If any of the matching entries have the same location as the constant and were
      # defined in the same file, then it is that constant's declaration
      declaration = matching_entries.any? do |e|
        e.uri == @uri && e.name_location == location
      end

      @references << Reference.new(name, location, declaration: declaration)
    end

    #: (String name, Prism::Location location, bool declaration) -> void
    def collect_instance_variable_references(name, location, declaration)
      return unless @target.is_a?(InstanceVariableTarget) && name == @target.name

      @references << Reference.new(name, location, declaration: declaration)
    end
  end
end
