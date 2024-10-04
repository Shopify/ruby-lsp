# typed: strict
# frozen_string_literal: true

module RubyLsp
  class RubyDocument < Document
    extend T::Sig
    extend T::Generic

    ParseResultType = type_member { { fixed: Prism::ParseResult } }

    class SorbetLevel < T::Enum
      enums do
        None = new("none")
        Ignore = new("ignore")
        False = new("false")
        True = new("true")
        Strict = new("strict")
      end
    end

    class << self
      extend T::Sig

      sig do
        params(
          node: Prism::Node,
          char_position: Integer,
          node_types: T::Array[T.class_of(Prism::Node)],
          encoding: Encoding,
        ).returns(NodeContext)
      end
      def locate(node, char_position, node_types: [], encoding: Encoding::UTF_8)
        queue = T.let(node.child_nodes.compact, T::Array[T.nilable(Prism::Node)])
        closest = node
        parent = T.let(nil, T.nilable(Prism::Node))
        nesting_nodes = T.let(
          [],
          T::Array[T.any(
            Prism::ClassNode,
            Prism::ModuleNode,
            Prism::SingletonClassNode,
            Prism::DefNode,
            Prism::BlockNode,
            Prism::LambdaNode,
            Prism::ProgramNode,
          )],
        )

        nesting_nodes << node if node.is_a?(Prism::ProgramNode)
        call_node = T.let(nil, T.nilable(Prism::CallNode))

        until queue.empty?
          candidate = queue.shift

          # Skip nil child nodes
          next if candidate.nil?

          # Add the next child_nodes to the queue to be processed. The order here is important! We want to move in the
          # same order as the visiting mechanism, which means searching the child nodes before moving on to the next
          # sibling
          T.unsafe(queue).unshift(*candidate.child_nodes)

          # Skip if the current node doesn't cover the desired position
          loc = candidate.location
          loc_start_offset = loc.start_code_units_offset(encoding)
          loc_end_offset = loc.end_code_units_offset(encoding)
          next unless (loc_start_offset...loc_end_offset).cover?(char_position)

          # If the node's start character is already past the position, then we should've found the closest node
          # already
          break if char_position < loc_start_offset

          # If the candidate starts after the end of the previous nesting level, then we've exited that nesting level
          # and need to pop the stack
          previous_level = nesting_nodes.last
          if previous_level &&
              (loc_start_offset > previous_level.location.end_code_units_offset(encoding))
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
            if (arg_loc && (arg_loc.start_code_units_offset(encoding)...
                            arg_loc.end_code_units_offset(encoding)).cover?(char_position)) ||
                (blk_loc && (blk_loc.start_code_units_offset(encoding)...
                            blk_loc.end_code_units_offset(encoding)).cover?(char_position))
              call_node = candidate
            end
          end

          # If there are node types to filter by, and the current node is not one of those types, then skip it
          next if node_types.any? && node_types.none? { |type| candidate.class == type }

          # If the current node is narrower than or equal to the previous closest node, then it is more precise
          closest_loc = closest.location
          closest_node_start_offset = closest_loc.start_code_units_offset(encoding)
          closest_node_end_offset = closest_loc.end_code_units_offset(encoding)
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

    sig { override.returns(T::Boolean) }
    def parse!
      return false unless @needs_parsing

      @needs_parsing = false
      @parse_result = Prism.parse(@source)
      true
    end

    sig { override.returns(T::Boolean) }
    def syntax_error?
      @parse_result.failure?
    end

    sig { override.returns(LanguageId) }
    def language_id
      LanguageId::Ruby
    end

    sig { returns(SorbetLevel) }
    def sorbet_level
      sigil = parse_result.magic_comments.find do |comment|
        comment.key == "typed"
      end&.value

      case sigil
      when "ignore"
        SorbetLevel::Ignore
      when "false"
        SorbetLevel::False
      when "true"
        SorbetLevel::True
      when "strict", "strong"
        SorbetLevel::Strict
      else
        SorbetLevel::None
      end
    end

    sig do
      params(
        range: T::Hash[Symbol, T.untyped],
        node_types: T::Array[T.class_of(Prism::Node)],
      ).returns(T.nilable(Prism::Node))
    end
    def locate_first_within_range(range, node_types: [])
      scanner = create_scanner
      start_position = scanner.find_char_position(range[:start])
      end_position = scanner.find_char_position(range[:end])
      desired_range = (start_position...end_position)
      queue = T.let(@parse_result.value.child_nodes.compact, T::Array[T.nilable(Prism::Node)])

      until queue.empty?
        candidate = queue.shift

        # Skip nil child nodes
        next if candidate.nil?

        # Add the next child_nodes to the queue to be processed. The order here is important! We want to move in the
        # same order as the visiting mechanism, which means searching the child nodes before moving on to the next
        # sibling
        T.unsafe(queue).unshift(*candidate.child_nodes)

        # Skip if the current node doesn't cover the desired position
        loc = candidate.location

        if desired_range.cover?(loc.start_offset...loc.end_offset) &&
            (node_types.empty? || node_types.any? { |type| candidate.class == type })
          return candidate
        end
      end
    end

    sig do
      params(
        position: T::Hash[Symbol, T.untyped],
        node_types: T::Array[T.class_of(Prism::Node)],
      ).returns(NodeContext)
    end
    def locate_node(position, node_types: [])
      RubyDocument.locate(
        @parse_result.value,
        create_scanner.find_char_position(position),
        node_types: node_types,
        encoding: @encoding,
      )
    end
  end
end
