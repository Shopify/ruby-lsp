# typed: strict
# frozen_string_literal: true

module RubyLsp
  # A minimalistic type checker to try to resolve types that can be inferred without requiring a type system or
  # annotations
  class TypeInferrer
    #: (RubyIndexer::Index index) -> void
    def initialize(index)
      @index = index
    end

    #: (NodeContext node_context) -> Type?
    def infer_receiver_type(node_context)
      node = node_context.node

      case node
      when Prism::CallNode
        infer_receiver_for_call_node(node, node_context)
      when Prism::InstanceVariableReadNode, Prism::InstanceVariableAndWriteNode, Prism::InstanceVariableWriteNode,
        Prism::InstanceVariableOperatorWriteNode, Prism::InstanceVariableOrWriteNode, Prism::InstanceVariableTargetNode,
        Prism::SuperNode, Prism::ForwardingSuperNode
        self_receiver_handling(node_context)
      when Prism::ClassVariableAndWriteNode, Prism::ClassVariableWriteNode, Prism::ClassVariableOperatorWriteNode,
        Prism::ClassVariableOrWriteNode, Prism::ClassVariableReadNode, Prism::ClassVariableTargetNode
        infer_receiver_for_class_variables(node_context)
      end
    end

    private

    #: (Prism::CallNode node, NodeContext node_context) -> Type?
    def infer_receiver_for_call_node(node, node_context)
      receiver = node.receiver

      # For receivers inside parenthesis, such as ranges like (0...2), we need to unwrap the parenthesis to get the
      # actual node
      if receiver.is_a?(Prism::ParenthesesNode)
        statements = receiver.body

        if statements.is_a?(Prism::StatementsNode)
          body = statements.body

          if body.length == 1
            receiver = body.first
          end
        end
      end

      case receiver
      when Prism::SelfNode, nil
        self_receiver_handling(node_context)
      when Prism::StringNode
        Type.new("String")
      when Prism::SymbolNode
        Type.new("Symbol")
      when Prism::ArrayNode
        Type.new("Array")
      when Prism::HashNode
        Type.new("Hash")
      when Prism::IntegerNode
        Type.new("Integer")
      when Prism::FloatNode
        Type.new("Float")
      when Prism::RegularExpressionNode
        Type.new("Regexp")
      when Prism::NilNode
        Type.new("NilClass")
      when Prism::TrueNode
        Type.new("TrueClass")
      when Prism::FalseNode
        Type.new("FalseClass")
      when Prism::RangeNode
        Type.new("Range")
      when Prism::LambdaNode
        Type.new("Proc")
      when Prism::ConstantPathNode, Prism::ConstantReadNode
        # When the receiver is a constant reference, we have to try to resolve it to figure out the right
        # receiver. But since the invocation is directly on the constant, that's the singleton context of that
        # class/module
        receiver_name = RubyIndexer::Index.constant_name(receiver)
        return unless receiver_name

        resolved_receiver = @index.resolve(receiver_name, node_context.nesting)
        name = resolved_receiver&.first&.name
        return unless name

        *parts, last = name.split("::")
        return Type.new("#{last}::<Class:#{last}>") if parts.empty?

        Type.new("#{parts.join("::")}::#{last}::<Class:#{last}>")
      when Prism::CallNode
        raw_receiver = receiver.message

        if raw_receiver == "new"
          # When invoking `new`, we recursively infer the type of the receiver to get the class type its being invoked
          # on and then return the attached version of that type, since it's being instantiated.
          type = infer_receiver_for_call_node(receiver, node_context)

          return unless type

          # If the method `new` was overridden, then we cannot assume that it will return a new instance of the class
          new_method = @index.resolve_method("new", type.name)&.first
          return if new_method && new_method.owner&.name != "Class"

          type.attached
        elsif raw_receiver
          guess_type(raw_receiver, node_context.nesting)
        end
      else
        guess_type(receiver.slice, node_context.nesting)
      end
    end

    #: (String raw_receiver, Array[String] nesting) -> GuessedType?
    def guess_type(raw_receiver, nesting)
      guessed_name = raw_receiver
        .delete_prefix("@")
        .delete_prefix("@@")
        .split("_")
        .map(&:capitalize)
        .join

      entries = @index.resolve(guessed_name, nesting) || @index.first_unqualified_const(guessed_name)
      name = entries&.first&.name
      return unless name

      GuessedType.new(name)
    end

    #: (NodeContext node_context) -> Type
    def self_receiver_handling(node_context)
      nesting = node_context.nesting
      # If we're at the top level, then the invocation is happening on `<main>`, which is a special singleton that
      # inherits from Object
      return Type.new("Object") if nesting.empty?
      return Type.new(node_context.fully_qualified_name) if node_context.surrounding_method

      # If we're not inside a method, then we're inside the body of a class or module, which is a singleton
      # context.
      #
      # If the class/module definition is using compact style (e.g.: `class Foo::Bar`), then we need to split the name
      # into its individual parts to build the correct singleton name
      parts = nesting.flat_map { |part| part.split("::") }
      Type.new("#{parts.join("::")}::<Class:#{parts.last}>")
    end

    #: (NodeContext node_context) -> Type?
    def infer_receiver_for_class_variables(node_context)
      nesting_parts = node_context.nesting.dup

      return Type.new("Object") if nesting_parts.empty?

      nesting_parts.reverse_each do |part|
        break unless part.include?("<Class:")

        nesting_parts.pop
      end

      receiver_name = nesting_parts.join("::")
      resolved_receiver = @index.resolve(receiver_name, node_context.nesting)&.first
      return unless resolved_receiver&.name

      Type.new(resolved_receiver.name)
    end

    # A known type
    class Type
      #: String
      attr_reader :name

      #: (String name) -> void
      def initialize(name)
        @name = name
      end

      # Returns the attached version of this type by removing the `<Class:...>` part from its name
      #: -> Type
      def attached
        Type.new(
          @name.split("::")[..-2] #: as !nil
          .join("::"),
        )
      end
    end

    # A type that was guessed based on the receiver raw name
    class GuessedType < Type
    end
  end
end
