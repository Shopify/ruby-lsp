# typed: false
# frozen_string_literal: true

require "test_helper"

class SemanticTokenEncoderTest < Minitest::Test
  TokenStub = RubyLsp::Requests::SemanticHighlighting::SemanticToken
  LocationStub = Struct.new(:start_line, :start_column)

  def test_tokens_encoded_to_relative_positioning
    tokens = [
      TokenStub.new(LocationStub.new(1, 2), 1, 0, 0),
      TokenStub.new(LocationStub.new(1, 4), 2, 9, 0),
      TokenStub.new(LocationStub.new(2, 2), 3, 0, 6),
      TokenStub.new(LocationStub.new(5, 6), 10, 4, 4),
    ]

    expected_encoding = [
      0, 2, 1, 0, 0,
      0, 2, 2, 9, 0,
      1, 2, 3, 0, 6,
      3, 6, 10, 4, 4,
    ]

    assert_equal(expected_encoding,
      RubyLsp::Requests::Support::SemanticTokenEncoder.new.encode(tokens).data)
  end

  def test_tokens_sorted_before_encoded
    tokens = [
      TokenStub.new(LocationStub.new(1, 2), 1, 0, 0),
      TokenStub.new(LocationStub.new(5, 6), 10, 4, 4),
      TokenStub.new(LocationStub.new(2, 2), 3, 0, 6),
      TokenStub.new(LocationStub.new(1, 4), 2, 9, 0),
    ]

    expected_encoding = [
      0, 2, 1, 0, 0,
      0, 2, 2, 9, 0,
      1, 2, 3, 0, 6,
      3, 6, 10, 4, 4,
    ]

    assert_equal(expected_encoding,
      RubyLsp::Requests::Support::SemanticTokenEncoder.new.encode(tokens).data)
  end
end
