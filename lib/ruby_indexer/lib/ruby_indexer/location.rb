# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Location
    # Pack 4 integers into a single Fixnum to eliminate ivar table overhead.
    # Layout (62 bits total, fits in a 63-bit tagged fixnum):
    #   bits 0-11:  start_column (12 bits, max 4095)
    #   bits 12-23: end_column   (12 bits, max 4095)
    #   bits 24-42: start_line   (19 bits, max 524287)
    #   bits 43-61: end_line     (19 bits, max 524287)

    COLUMN_BITS = 12
    LINE_BITS = 19
    COLUMN_MASK = (1 << COLUMN_BITS) - 1 # 0xFFF
    LINE_MASK = (1 << LINE_BITS) - 1     # 0x7FFFF

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

      # Returns a packed Integer representing the location data without creating a Location object.
      # Use with Location.from_packed to reconstruct the Location later.
      #: (Prism::Location prism_location, (^(Integer arg0) -> Integer | Prism::CodeUnitsCache) code_units_cache) -> Integer
      def pack_prism_location(prism_location, code_units_cache)
        start_column = prism_location.cached_start_code_units_column(code_units_cache)
        end_column = prism_location.cached_end_code_units_column(code_units_cache)
        start_line = prism_location.start_line
        end_line = prism_location.end_line

        (start_column & COLUMN_MASK) |
          ((end_column & COLUMN_MASK) << COLUMN_BITS) |
          ((start_line & LINE_MASK) << (COLUMN_BITS * 2)) |
          ((end_line & LINE_MASK) << (COLUMN_BITS * 2 + LINE_BITS))
      end

      # Creates a Location from a packed Integer
      #: (Integer packed) -> instance
      def from_packed(packed)
        loc = allocate
        loc.instance_variable_set(:@packed, packed)
        loc
      end
    end

    #: (Integer start_line, Integer end_line, Integer start_column, Integer end_column) -> void
    def initialize(start_line, end_line, start_column, end_column)
      @packed = (start_column & COLUMN_MASK) |
        ((end_column & COLUMN_MASK) << COLUMN_BITS) |
        ((start_line & LINE_MASK) << (COLUMN_BITS * 2)) |
        ((end_line & LINE_MASK) << (COLUMN_BITS * 2 + LINE_BITS)) #: Integer
    end

    #: -> Integer
    def start_line
      (@packed >> (COLUMN_BITS * 2)) & LINE_MASK
    end

    #: -> Integer
    def end_line
      (@packed >> (COLUMN_BITS * 2 + LINE_BITS)) & LINE_MASK
    end

    #: -> Integer
    def start_column
      @packed & COLUMN_MASK
    end

    #: -> Integer
    def end_column
      (@packed >> COLUMN_BITS) & COLUMN_MASK
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
