# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    # @abstract
    class ResponseBuilder
      #: (Encoding, Prism::ParseLexResult) -> void
      def initialize(encoding, parse_result)
        @encoding = encoding
        @code_units_cache = parse_result.code_units_cache(encoding) #: (^(Integer arg0) -> Integer | Prism::CodeUnitsCache)
      end

      #: (Prism::Location) -> Interface::Range
      def range_from_location(location)
        Interface::Range.new(
          start: Interface::Position.new(line: location.start_line - 1, character: location.cached_start_code_units_column(@code_units_cache)),
          end: Interface::Position.new(line: location.end_line - 1, character: location.cached_end_code_units_column(@code_units_cache)),
        )
      end

      #: (Prism::Node) -> Interface::Range
      def range_from_node(node)
        range_from_location(node.location)
      end

      # @abstract
      #: -> top
      def response
        raise AbstractMethodInvokedError
      end
    end
  end
end
