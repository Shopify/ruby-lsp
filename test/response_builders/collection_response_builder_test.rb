# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class CollectionResponseBuilderTest < Minitest::Test
    def test_range_from_location_respects_negotiated_position_encoding
      # Offsets for `foo` on the single line "🌍café"; foo:
      #          "   🌍   c   a   f   é   "   ;   _   | foo
      #  bytes   1    4   1   1   1   2   1   1   1   | 13..16
      #  utf16   1    2   1   1   1   1   1   1   1   | 10..13
      #  utf32   1    1   1   1   1   1   1   1   1   |  9..12
      source = "\"🌍café\"; foo"
      parse_result = Prism.parse_lex(source)
      location = parse_result.value[0].statements.body.last.location

      # UTF-8: number of bytes
      assert_range(
        ResponseBuilders::CollectionResponseBuilder.new(Encoding::UTF_8, parse_result).range_from_location(location),
        start_character: 13,
        end_character: 16,
      )

      # UTF-16: number of UTF-16 code units (length 1 for 1/2 byte characters, length 2 for 3/4 byte characters)
      assert_range(
        ResponseBuilders::CollectionResponseBuilder.new(Encoding::UTF_16LE, parse_result).range_from_location(location),
        start_character: 10,
        end_character: 13,
      )

      # UTF-32: number of UTF-32 code points (length 1 for all characters)
      assert_range(
        ResponseBuilders::CollectionResponseBuilder.new(Encoding::UTF_32LE, parse_result).range_from_location(location),
        start_character: 9,
        end_character: 12,
      )
    end

    private

    #: (Interface::Range, start_character: Integer, end_character: Integer) -> void
    def assert_range(range, start_character:, end_character:)
      assert_equal(0, range.start.line)
      assert_equal(0, range.end.line)
      assert_equal(start_character, range.start.character)
      assert_equal(end_character, range.end.character)
    end
  end
end
