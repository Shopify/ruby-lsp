# typed: true
# frozen_string_literal: true

require "test_helper"

class SemanticTokensDeltaTest < Minitest::Test
  def test_inserting_something_at_the_end
    assert_expected_token_result(
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 100, 200, 300, 400, 500],
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    )
  end

  def test_inserting_something_in_the_beginning
    assert_expected_token_result(
      [10, 100, 200, 300, 400, 500, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    )
  end

  def test_inserting_something_in_the_middle
    assert_expected_token_result(
      [1, 2, 3, 4, 5, 10, 100, 200, 300, 400, 500, 6, 7, 8, 9, 10],
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    )
  end

  def test_deleting_at_the_end
    assert_expected_token_result(
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 100, 200, 300, 400, 500],
    )
  end

  def test_deleting_at_the_beginning
    assert_expected_token_result(
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      [10, 100, 200, 300, 400, 500, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    )
  end

  def test_deleting_in_the_middle
    assert_expected_token_result(
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      [1, 2, 3, 4, 5, 10, 100, 200, 300, 400, 500, 6, 7, 8, 9, 10],
    )
  end

  # The scenarios below were captured with the responses from the language server automatically, so that we can have a
  # few more real case tests. There are confounding aspects to these examples, like having the exact same semantic token
  # in arrays with different lengths

  def test_computing_deltas_1
    assert_expected_token_result(
      [3, 4, 3, 13, 1, 1, 2, 1, 8, 0, 1, 0, 1, 13, 0, 1, 2, 9, 13, 0, 1, 2, 1, 8, 0],
      [3, 4, 3, 13, 1, 1, 2, 1, 8, 0, 2, 2, 9, 13, 0, 1, 2, 1, 8, 0],
    )
  end

  def test_computing_deltas_2
    assert_expected_token_result(
      [
        3,
        4,
        21,
        13,
        1,
        1,
        2,
        12,
        13,
        0,
        0,
        73,
        5,
        13,
        0,
        2,
        2,
        5,
        8,
        0,
        0,
        8,
        7,
        0,
        0,
        0,
        9,
        8,
        0,
        0,
        0,
        10,
        20,
        0,
        0,
        0,
        21,
        13,
        13,
        0,
        4,
        4,
        5,
        13,
        0,
        2,
        0,
        1,
        8,
        0,
        1,
        0,
        1,
        8,
        0,
        2,
        2,
        12,
        13,
        0,
        0,
        73,
        5,
        8,
        0,
      ],
      [
        3,
        4,
        21,
        13,
        1,
        1,
        2,
        12,
        13,
        0,
        0,
        73,
        5,
        13,
        0,
        2,
        2,
        5,
        8,
        0,
        0,
        8,
        7,
        0,
        0,
        0,
        9,
        8,
        0,
        0,
        0,
        10,
        20,
        0,
        0,
        0,
        21,
        13,
        13,
        0,
        4,
        4,
        5,
        13,
        0,
        2,
        0,
        1,
        8,
        0,
        3,
        2,
        12,
        13,
        0,
        0,
        73,
        5,
        8,
        0,
      ],
    )
  end

  def test_computing_deltas_3
    assert_expected_token_result(
      [3, 6, 3, 2, 1, 0, 0, 3, 0, 0, 1, 6, 4, 13, 1, 1, 4, 1, 8, 0],
      [3, 6, 3, 2, 1, 0, 0, 3, 0, 0, 1, 6, 4, 13, 1],
    )
  end

  def test_computing_delta_4
    assert_expected_token_result(
      [3, 6, 3, 2, 1, 0, 0, 3, 0, 0, 1, 6, 4, 13, 1, 1, 4, 1, 8, 0, 1, 4, 1, 8, 0],
      [3, 6, 3, 2, 1, 0, 0, 3, 0, 0, 1, 6, 4, 13, 1, 1, 4, 1, 8, 0],
    )
  end

  def test_computing_delta_5
    assert_expected_token_result(
      [3, 6, 3, 2, 1, 0, 0, 3, 0, 0, 1, 6, 4, 13, 1, 1, 4, 1, 8, 0, 1, 4, 1, 8, 0, 0, 2, 4, 13, 0],
      [3, 6, 3, 2, 1, 0, 0, 3, 0, 0, 1, 6, 4, 13, 1, 1, 4, 1, 8, 0, 1, 4, 1, 8, 0, 0, 2, 4, 13, 0, 1, 4, 1, 8, 0],
    )
  end

  def test_computing_delta_6
    assert_expected_token_result(
      [3, 6, 3, 2, 1, 0, 0, 3, 0, 0, 1, 6, 4, 13, 1, 1, 4, 1, 8, 0, 1, 4, 1, 8, 0, 0, 2, 4, 13, 0],
      [3, 6, 3, 2, 1, 0, 0, 3, 0, 0, 1, 6, 4, 13, 1, 1, 4, 1, 8, 0, 1, 4, 1, 8, 0, 1, 4, 1, 8, 0, 0, 2, 4, 13, 0],
    )
  end

  def test_computing_delta_7
    assert_expected_token_result(
      [
        3,
        6,
        3,
        2,
        1,
        0,
        0,
        3,
        0,
        0,
        1,
        6,
        4,
        13,
        1,
        1,
        4,
        1,
        8,
        0,
        1,
        4,
        1,
        8,
        0,
        0,
        2,
        2,
        13,
        0,
        1,
        4,
        1,
        8,
        0,
        0,
        2,
        4,
        13,
        0,
      ],
      [
        3,
        6,
        3,
        2,
        1,
        0,
        0,
        3,
        0,
        0,
        1,
        6,
        4,
        13,
        1,
        1,
        4,
        1,
        8,
        0,
        1,
        4,
        1,
        8,
        0,
        0,
        2,
        1,
        13,
        0,
        1,
        4,
        1,
        8,
        0,
        0,
        2,
        4,
        13,
        0,
      ],
    )
  end

  private

  def assert_expected_token_result(current_tokens, previous_tokens)
    edit = RubyLsp::Requests::SemanticHighlighting.compute_delta(current_tokens, previous_tokens, "1").edits.first

    previous_tokens[edit[:start]...(edit[:start] + edit[:deleteCount])] = edit[:data]
    assert_equal(current_tokens, previous_tokens)
  end
end
