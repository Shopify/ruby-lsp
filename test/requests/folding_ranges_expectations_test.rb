# typed: false
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class FoldingRangesExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::FoldingRanges, "folding_ranges"
end
