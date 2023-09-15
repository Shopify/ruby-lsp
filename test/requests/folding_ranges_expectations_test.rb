# typed: strict
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

module RubyLsp
  class FoldingRangesExpectationsTest < ExpectationsTestRunner
    expectations_tests Requests::FoldingRanges, "folding_ranges"
  end
end
