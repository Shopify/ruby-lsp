# typed: true
# frozen_string_literal: true

require "test_helper"

class SemanticTokenEncoderTest < Minitest::Test
  SemanticTokenEncoder = RubyLsp::ResponseBuilders::SemanticHighlighting::SemanticTokenEncoder
  def test_tokens_encoded_to_relative_positioning
    tokens = [
      stub_token(1, 2, 1, 0, [0]),
      stub_token(1, 4, 2, 9, [0]),
      stub_token(2, 2, 3, 0, [6]),
      stub_token(5, 6, 10, 4, [4]),
    ]

    expected_encoding = [
      0,
      2,
      1,
      0,
      1,
      0,
      2,
      2,
      9,
      1,
      1,
      2,
      3,
      0,
      64,
      3,
      6,
      10,
      4,
      16,
    ]

    assert_equal(
      expected_encoding,
      SemanticTokenEncoder.new.encode(tokens),
    )
  end

  def test_tokens_sorted_before_encoded
    tokens = [
      stub_token(1, 2, 1, 0, [0]),
      stub_token(5, 6, 10, 4, [4]),
      stub_token(2, 2, 3, 0, [6]),
      stub_token(1, 4, 2, 9, [0]),
    ]

    expected_encoding = [
      0,
      2,
      1,
      0,
      1,
      0,
      2,
      2,
      9,
      1,
      1,
      2,
      3,
      0,
      64,
      3,
      6,
      10,
      4,
      16,
    ]

    assert_equal(expected_encoding, SemanticTokenEncoder.new.encode(tokens))
  end

  def test_encoded_modifiers_with_no_modifiers
    bit_flag = SemanticTokenEncoder.new.encode_modifiers([])
    assert_equal(0b0000000000, bit_flag)
  end

  def test_encoded_modifiers_with_one_modifier
    bit_flag = SemanticTokenEncoder.new.encode_modifiers([9])
    assert_equal(0b1000000000, bit_flag)
  end

  def test_encoded_modifiers_with_some_modifiers
    bit_flag = SemanticTokenEncoder.new.encode_modifiers([1, 3, 9, 7, 5])
    assert_equal(0b1010101010, bit_flag)
  end

  private

  def stub_token(start_line, start_column, length, type, modifier)
    RubyLsp::ResponseBuilders::SemanticHighlighting::SemanticToken.new(
      start_line: start_line,
      start_code_unit_column: start_column,
      length: length,
      type: type,
      modifier: modifier,
    )
  end
end
