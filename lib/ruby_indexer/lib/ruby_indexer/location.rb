# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Location
    class << self
      #: (Prism::Location prism_location, (^(Integer arg0) -> Integer | Prism::CodeUnitsCache) code_units_cache) -> instance
      def from_prism_location(prism_location, code_units_cache)
        new(
          prism_location.start_line,
          prism_location.end_line,
          prism_location.cached_start_code_units_column(code_units_cache),
          prism_location.cached_end_code_units_column(code_units_cache),
        )
      end
    end

    #: Integer
    attr_reader :start_line, :end_line, :start_column, :end_column

    #: (Integer start_line, Integer end_line, Integer start_column, Integer end_column) -> void
    def initialize(start_line, end_line, start_column, end_column)
      @start_line = start_line
      @end_line = end_line
      @start_column = start_column
      @end_column = end_column
    end

    #: ((Location | Prism::Location) other) -> bool
    def ==(other)
      start_line == other.start_line &&
        end_line == other.end_line &&
        start_column == other.start_column &&
        end_column == other.end_column
    end
  end
end
