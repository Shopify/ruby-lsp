# frozen_string_literal: true

require "test_helper"

class FoldingRangesTest < Minitest::Test
  def test_folding_method_definitions
    ranges = [{ startLine: 0, endLine: 3, kind: "region" }]
    assert_ranges(<<~RUBY, ranges)
      def foo
        a = 2
        puts "a"
      end
    RUBY
  end

  private

  def assert_ranges(source, expected_ranges)
    parsed_tree = Ruby::Lsp::Store::ParsedTree.new(source)
    actual = Ruby::Lsp::Requests::FoldingRanges.run(parsed_tree)
    assert_equal(expected_ranges, JSON.parse(actual.to_json, symbolize_names: true))
  end
end
