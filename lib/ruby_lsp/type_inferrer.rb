# typed: strict
# frozen_string_literal: true

module RubyLsp
  # A minimalistic type checker to try to resolve types that can be inferred without requiring a type system or
  # annotations
  class TypeInferrer
    extend T::Sig

    sig { params(index: RubyIndexer::Index).void }
    def initialize(index)
      @index = index
    end

    sig { params(node_context: NodeContext).returns(T.nilable(Type)) }
    def infer_receiver_type(node_context)
      node = node_context.node

      case node
      when Prism::CallNode
        infer_receiver_for_call_node(node, node_context)
      when Prism::InstanceVariableReadNode, Prism::InstanceVariableAndWriteNode, Prism::InstanceVariableWriteNode,
        Prism::InstanceVariableOperatorWriteNode, Prism::InstanceVariableOrWriteNode, Prism::InstanceVariableTargetNode,
        Prism::SuperNode, Prism::ForwardingSuperNode
        self_receiver_handling(node_context)
      end
    end

    private

    sig { params(node: Prism::CallNode, node_context: NodeContext).returns(T.nilable(Type)) }
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
        receiver_name = constant_name(receiver)
        return unless receiver_name

        resolved_receiver = @index.resolve(receiver_name, node_context.nesting)
        name = resolved_receiver&.first&.name
        return unless name

        *parts, last = name.split("::")
        return Type.new("#{last}::<Class:#{last}>") if parts.empty?

        Type.new("#{parts.join("::")}::#{last}::<Class:#{last}>")
      else

        raw_receiver = if receiver.is_a?(Prism::CallNode)
          receiver.message
        else
          receiver&.slice
        end

        if raw_receiver
          guessed_name = raw_receiver
            .delete_prefix("@")
            .delete_prefix("@@")
            .split("_")
            .map(&:capitalize)
            .join

          entries = @index.resolve(guessed_name, node_context.nesting) || @index.first_unqualified_const(guessed_name)
          name = entries&.first&.name
          GuessedType.new(name) if name
        end
      end
    end

    sig { params(node_context: NodeContext).returns(Type) }
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

    sig do
      params(
        node: T.any(
          Prism::ConstantPathNode,
          Prism::ConstantReadNode,
        ),
      ).returns(T.nilable(String))
    end
    def constant_name(node)
      node.full_name
    rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError,
           Prism::ConstantPathNode::MissingNodesInConstantPathError
      nil
    end

    # A known type
    class Type
      extend T::Sig

      sig { returns(String) }
      attr_reader :name

      sig { params(name: String).void }
      def initialize(name)
        @name = name
      end
    end

    # A type that was guessed based on the receiver raw name
    class GuessedType < Type
    end
  end
end
