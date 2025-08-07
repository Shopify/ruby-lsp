# typed: false
# frozen_string_literal: true

require "test-unit"

class SampleTest < Test::Unit::TestCase
  raise "oh, no"

  def test_that_passes
    assert_equal(1, 1)
  end
end
