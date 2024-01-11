# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class SelectionRangesExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::SelectionRanges, "selection_ranges"

  def run_expectations(source)
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: URI("file:///fake.rb"))
    actual = RubyLsp::Requests::SelectionRanges.new(document).perform
    params = @__params&.any? ? @__params : default_args

    filtered = params.map { |position| actual.find { |range| range.cover?(position) } }
    filtered
  end

  private

  def default_args
    [{ line: 0, character: 0 }]
  end
end
