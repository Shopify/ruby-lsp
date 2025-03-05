# frozen_string_literal: true

require "test_helper"

# We are only testing the output of the runner, there's no need for to be random.
Minitest::Test.i_suck_and_my_tests_are_order_dependent!

class Sample < Minitest::Test
  def test_that_passes
    assert_equal(1, 1)
    assert_equal(2, 2)
  end

  def test_that_fails
    assert_equal(1, 2)
  end

  def test_that_is_pending
    skip("pending test")
  end

  def test_that_raises
    raise "oops"
  end
end
