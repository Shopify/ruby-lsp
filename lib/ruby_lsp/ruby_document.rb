# typed: strict
# frozen_string_literal: true

module RubyLsp
  class RubyDocument < Document
    class SorbetLevel < T::Enum
      enums do
        None = new("none")
        Ignore = new("ignore")
        False = new("false")
        True = new("true")
        Strict = new("strict")
      end
    end

    sig { override.returns(Prism::ParseResult) }
    def parse
      return @parse_result unless @needs_parsing

      @needs_parsing = false
      @parse_result = Prism.parse(@source)
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
  end
end
