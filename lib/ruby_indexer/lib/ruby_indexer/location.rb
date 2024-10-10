# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Location
    extend T::Sig

    class << self
      extend T::Sig

      sig { params(prism_location: Prism::Location, encoding: Encoding).returns(T.attached_class) }
      def from_prism_location(prism_location, encoding)
        new(
          prism_location.start_line,
          prism_location.end_line,
          prism_location.start_code_units_column(encoding),
          prism_location.end_code_units_column(encoding),
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
