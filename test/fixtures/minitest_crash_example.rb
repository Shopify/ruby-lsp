# frozen_string_literal: true

require "minitest/autorun"

Minitest::Test.i_suck_and_my_tests_are_order_dependent!

class SampleTest < Minitest::Test
  raise "oh, no"

  def test_that_passes
    assert_equal(1, 1)
  end
end
