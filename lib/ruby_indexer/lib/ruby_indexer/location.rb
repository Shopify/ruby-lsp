# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Location
    extend T::Sig

    class << self
      extend T::Sig

      sig do
        params(
          prism_location: Prism::Location,
          code_units_cache: T.any(
            T.proc.params(arg0: Integer).returns(Integer),
            Prism::CodeUnitsCache,
          ),
        ).returns(T.attached_class)
      end
      def from_prism_location(prism_location, code_units_cache)
        new(
          prism_location.start_line,
          prism_location.end_line,
          prism_location.cached_start_code_units_column(code_units_cache),
          prism_location.cached_end_code_units_column(code_units_cache),
        )
      end
    end

    sig { returns(Integer) }
    attr_reader :start_line, :end_line, :start_column, :end_column

    sig do
      params(
        start_line: Integer,
        end_line: Integer,
        start_column: Integer,
        end_column: Integer,
      ).void
    end
    def initialize(start_line, end_line, start_column, end_column)
      @start_line = start_line
      @end_line = end_line
      @start_column = start_column
      @end_column = end_column
    end
  end
end
