# typed: strict
# frozen_string_literal: true

module Rubydex
  class Signature
    # Returns a string with the decorated names of the parameters of this signature, e.g.
    # `(a, b = <default>, *c, d, e:, f: <default>, **g, &h)`.
    #: () -> String
    def format
      parameters.map { |param| decorated_name(param) }.join(", ")
    end

    # Returns `true` if the given call node arguments array matches this signature. The matching is intentionally lenient
    # because this method is used to detect which overload should be displayed in signature help while the user is still
    # typing the call. We prefer returning `true` for situations that cannot be analyzed statically (e.g. presence of
    # splats, keyword splats, forwarding) and accept missing arguments since the user may not be done typing yet.
    #: (Array[Prism::Node] arguments) -> bool
    def matches?(arguments)
      min_pos = 0
      max_pos = 0 #: (Integer | Float)
      names = []
      has_forward = false #: bool
      has_keyword_rest = false #: bool

      parameters.each do |param|
        case param
        when PositionalParameter, PostParameter
          min_pos += 1
          max_pos += 1
        when OptionalPositionalParameter
          max_pos += 1
        when RestPositionalParameter
          max_pos = Float::INFINITY
        when ForwardParameter
          max_pos = Float::INFINITY
          has_forward = true
        when KeywordParameter, OptionalKeywordParameter
          names << param.name
        when RestKeywordParameter
          has_keyword_rest = true
        end
      end

      keyword_hash_nodes, positional_args = arguments.partition { |arg| arg.is_a?(Prism::KeywordHashNode) }
      keyword_args = keyword_hash_nodes.first #: as Prism::KeywordHashNode?
        &.elements
      forwarding_arguments, positionals = positional_args.partition do |arg|
        arg.is_a?(Prism::ForwardingArgumentsNode)
      end

      return true if has_forward && min_pos == 0

      # If the only argument passed is a forwarding argument, then anything will match
      (positionals.empty? && forwarding_arguments.any?) ||
        (
          positional_arguments_match?(positionals, forwarding_arguments, keyword_args, min_pos, max_pos) &&
          (has_forward || has_keyword_rest || keyword_arguments_match?(keyword_args, names))
        )
    end

    private

    #: (Parameter) -> String
    def decorated_name(param)
      case param
      when OptionalPositionalParameter
        "#{param.name} = <default>"
      when RestPositionalParameter
        "*#{param.name}"
      when KeywordParameter
        "#{param.name}:"
      when OptionalKeywordParameter
        "#{param.name}: <default>"
      when RestKeywordParameter
        "**#{param.name}"
      when BlockParameter
        "&#{param.name}"
      else
        param.name.to_s
      end
    end

    #: (Array[Prism::Node] positional_args, Array[Prism::Node] forwarding_arguments, Array[Prism::Node]? keyword_args, Integer min_pos, (Integer | Float) max_pos) -> bool
    def positional_arguments_match?(positional_args, forwarding_arguments, keyword_args, min_pos, max_pos)
      (min_pos > 0 && positional_args.any? { |arg| arg.is_a?(Prism::SplatNode) }) ||
        (min_pos - positional_args.length > 0 && keyword_args&.any? { |arg| arg.is_a?(Prism::AssocSplatNode) }) ||
        (min_pos - positional_args.length > 0 && forwarding_arguments.any?) ||
        (min_pos > 0 && positional_args.length <= max_pos) ||
        (min_pos == 0 && positional_args.empty?)
    end

    #: (Array[Prism::Node]? args, Array[Symbol] names) -> bool
    def keyword_arguments_match?(args, names)
      return true unless args
      return true if args.any? { |arg| arg.is_a?(Prism::AssocSplatNode) }

      arg_names = args.filter_map do |arg|
        next unless arg.is_a?(Prism::AssocNode)

        key = arg.key
        key.value&.to_sym if key.is_a?(Prism::SymbolNode)
      end

      (arg_names - names).empty?
    end
  end
end
