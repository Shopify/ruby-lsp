# typed: false
# frozen_string_literal: true

require "test-unit"
require "ruby_lsp/test_unit_test_runner"

class SampleTest < Test::Unit::TestCase
  def test_that_passes
    assert_equal(1, 1)
    assert_equal(2, 2)
  end

  def test_that_fails
    assert_equal(1, 2)
  end

  def test_that_is_pending
    pend("pending test")
  end

  def test_that_raises
    raise "oops"
  end

  def test_with_output
    $stdout.puts "hello from $stdout.puts\nanother line"
    puts "hello from puts\nanother line"
    $stdout.write "hello from write\nanother line"
  end
end
