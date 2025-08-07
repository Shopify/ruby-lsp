# typed: strict
# frozen_string_literal: true

module RubyLsp
  #: [ParseResultType = Prism::ParseLexResult]
  class RubyDocument < Document
    METHODS_THAT_CHANGE_DECLARATIONS = [
      :private_constant,
      :attr_reader,
      :attr_writer,
      :attr_accessor,
      :alias_method,
      :include,
      :prepend,
      :extend,
      :public,
      :protected,
      :private,
      :module_function,
      :private_class_method,
    ].freeze

    class << self
      #: (Prism::Node node, Integer char_position, code_units_cache: (^(Integer arg0) -> Integer | Prism::CodeUnitsCache), ?node_types: Array[singleton(Prism::Node)]) -> NodeContext
      def locate(node, char_position, code_units_cache:, node_types: [])
        queue = node.child_nodes.compact #: Array[Prism::Node?]
        closest = node
        parent = nil #: Prism::Node?
        nesting_nodes = [] #: Array[(Prism::ClassNode | Prism::ModuleNode | Prism::SingletonClassNode | Prism::DefNode | Prism::BlockNode | Prism::LambdaNode | Prism::ProgramNode)]

        nesting_nodes << node if node.is_a?(Prism::ProgramNode)
        call_node = nil #: Prism::CallNode?

        until queue.empty?
          candidate = queue.shift

          # Skip nil child nodes
          next if candidate.nil?

          # Add the next child_nodes to the queue to be processed. The order here is important! We want to move in the
          # same order as the visiting mechanism, which means searching the child nodes before moving on to the next
          # sibling
          queue.unshift(*candidate.child_nodes)

          # Skip if the current node doesn't cover the desired position
          loc = candidate.location
          loc_start_offset = loc.cached_start_code_units_offset(code_units_cache)
          loc_end_offset = loc.cached_end_code_units_offset(code_units_cache)
          next unless (loc_start_offset...loc_end_offset).cover?(char_position)

          # If the node's start character is already past the position, then we should've found the closest node
          # already
          break if char_position < loc_start_offset

          # If the candidate starts after the end of the previous nesting level, then we've exited that nesting level
          # and need to pop the stack
          previous_level = nesting_nodes.last
          if previous_level &&
              (loc_start_offset > previous_level.location.cached_end_code_units_offset(code_units_cache))
            nesting_nodes.pop
          end

          # Keep track of the nesting where we found the target. This is used to determine the fully qualified name of
          # the target when it is a constant
          case candidate
          when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode, Prism::DefNode, Prism::BlockNode,
            Prism::LambdaNode
            nesting_nodes << candidate
          end

          if candidate.is_a?(Prism::CallNode)
            arg_loc = candidate.arguments&.location
            blk_loc = candidate.block&.location
            if (arg_loc && (arg_loc.cached_start_code_units_offset(code_units_cache)...
                            arg_loc.cached_end_code_units_offset(code_units_cache)).cover?(char_position)) ||
                (blk_loc && (blk_loc.cached_start_code_units_offset(code_units_cache)...
                            blk_loc.cached_end_code_units_offset(code_units_cache)).cover?(char_position))
              call_node = candidate
            end
          end

          # If there are node types to filter by, and the current node is not one of those types, then skip it
          next if node_types.any? && node_types.none? { |type| candidate.class == type }

          # If the current node is narrower than or equal to the previous closest node, then it is more precise
          closest_loc = closest.location
          closest_node_start_offset = closest_loc.cached_start_code_units_offset(code_units_cache)
          closest_node_end_offset = closest_loc.cached_end_code_units_offset(code_units_cache)
          if loc_end_offset - loc_start_offset <= closest_node_end_offset - closest_node_start_offset
            parent = closest
            closest = candidate
          end
        end

        # When targeting the constant part of a class/module definition, we do not want the nesting to be duplicated.
        # That is, when targeting Bar in the following example:
        #
        # ```ruby
        #   class Foo::Bar; end
        # ```
        # The correct target is `Foo::Bar` with an empty nesting. `Foo::Bar` should not appear in the nesting stack,
        # even though the class/module node does indeed enclose the target, because it would lead to incorrect behavior
        if closest.is_a?(Prism::ConstantReadNode) || closest.is_a?(Prism::ConstantPathNode)
          last_level = nesting_nodes.last

          if (last_level.is_a?(Prism::ModuleNode) || last_level.is_a?(Prism::ClassNode)) &&
              last_level.constant_path == closest
            nesting_nodes.pop
          end
        end

        NodeContext.new(closest, parent, nesting_nodes, call_node)
      end
    end

    #: (^(Integer arg0) -> Integer | Prism::CodeUnitsCache)
    attr_reader :code_units_cache

    #: (source: String, version: Integer, uri: URI::Generic, global_state: GlobalState) -> void
    def initialize(source:, version:, uri:, global_state:)
      super
      @code_units_cache = @parse_result
        .code_units_cache(@encoding) #: (^(Integer arg0) -> Integer | Prism::CodeUnitsCache)
    end

    # @override
    #: -> bool
    def parse!
      return false unless @needs_parsing

      @needs_parsing = false
      @parse_result = Prism.parse_lex(@source)
      @code_units_cache = @parse_result.code_units_cache(@encoding)
      true
    end

    #: -> Prism::ProgramNode
    def ast
      @parse_result.value.first
    end

    # @override
    #: -> bool
    def syntax_error?
      @parse_result.failure?
    end

    # @override
    #: -> Symbol
    def language_id
      :ruby
    end

    #: (Hash[Symbol, untyped] range, ?node_types: Array[singleton(Prism::Node)]) -> Prism::Node?
    def locate_first_within_range(range, node_types: [])
      start_position, end_position = find_index_by_position(range[:start], range[:end])

      desired_range = (start_position...end_position)
      queue = ast.child_nodes.compact #: Array[Prism::Node?]

      until queue.empty?
        candidate = queue.shift

        # Skip nil child nodes
        next if candidate.nil?

        # Add the next child_nodes to the queue to be processed. The order here is important! We want to move in the
        # same order as the visiting mechanism, which means searching the child nodes before moving on to the next
        # sibling
        queue.unshift(*candidate.child_nodes)

        # Skip if the current node doesn't cover the desired position
        loc = candidate.location

        if desired_range.cover?(loc.start_offset...loc.end_offset) &&
            (node_types.empty? || node_types.any? { |type| candidate.class == type })
          return candidate
        end
      end
    end

    #: (Hash[Symbol, untyped] position, ?node_types: Array[singleton(Prism::Node)]) -> NodeContext
    def locate_node(position, node_types: [])
      char_position, _ = find_index_by_position(position)

      RubyDocument.locate(
        ast,
        char_position,
        code_units_cache: @code_units_cache,
        node_types: node_types,
      )
    end

    #: -> bool
    def should_index?
      # This method controls when we should index documents. If there's no recent edit and the document has just been
      # opened, we need to index it
      return true unless @last_edit

      last_edit_may_change_declarations?
    end

    private

    #: -> bool
    def last_edit_may_change_declarations?
      case @last_edit
      when Delete
        # Not optimized yet. It's not trivial to identify that a declaration has been removed since the source is no
        # longer there and we don't remember the deleted text
        true
      when Insert, Replace
        position_may_impact_declarations?(@last_edit.range[:start])
      else
        false
      end
    end

    #: (Hash[Symbol, Integer] position) -> bool
    def position_may_impact_declarations?(position)
      node_context = locate_node(position)
      node_at_edit = node_context.node

      # Adjust to the parent when editing the constant of a class/module declaration
      if node_at_edit.is_a?(Prism::ConstantReadNode) || node_at_edit.is_a?(Prism::ConstantPathNode)
        node_at_edit = node_context.parent
      end

      case node_at_edit
      when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode, Prism::DefNode,
          Prism::ConstantPathWriteNode, Prism::ConstantPathOrWriteNode, Prism::ConstantPathOperatorWriteNode,
          Prism::ConstantPathAndWriteNode, Prism::ConstantOrWriteNode, Prism::ConstantWriteNode,
          Prism::ConstantAndWriteNode, Prism::ConstantOperatorWriteNode, Prism::GlobalVariableAndWriteNode,
          Prism::GlobalVariableOperatorWriteNode, Prism::GlobalVariableOrWriteNode, Prism::GlobalVariableTargetNode,
          Prism::GlobalVariableWriteNode, Prism::InstanceVariableWriteNode, Prism::InstanceVariableAndWriteNode,
          Prism::InstanceVariableOperatorWriteNode, Prism::InstanceVariableOrWriteNode,
          Prism::InstanceVariableTargetNode, Prism::AliasMethodNode
        true
      when Prism::MultiWriteNode
        [*node_at_edit.lefts, *node_at_edit.rest, *node_at_edit.rights].any? do |node|
          node.is_a?(Prism::ConstantTargetNode) || node.is_a?(Prism::ConstantPathTargetNode)
        end
      when Prism::CallNode
        receiver = node_at_edit.receiver
        (!receiver || receiver.is_a?(Prism::SelfNode)) && METHODS_THAT_CHANGE_DECLARATIONS.include?(node_at_edit.name)
      else
        false
      end
    end
  end
end
