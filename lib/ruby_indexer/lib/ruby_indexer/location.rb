# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Location
    extend T::Sig

    sig { returns(Integer) }
    attr_reader :start_line, :end_line, :start_column, :end_column, :start_code_units_column, :end_code_units_column

    sig do
      params(
        start_line: Integer,
        end_line: Integer,
        start_column: Integer,
        end_column: Integer,
        start_code_units_column: Integer,
        end_code_units_column: Integer,
      ).void
    end
    def initialize( # rubocop:disable Metrics/ParameterLists
      start_line,
      end_line,
      start_column,
      end_column,
      start_code_units_column,
      end_code_units_column
    )
      @start_line = start_line
      @end_line = end_line
      @start_column = start_column
      @end_column = end_column
      @start_code_units_column = start_code_units_column
      @end_code_units_column = end_code_units_column
    end
  end
end
