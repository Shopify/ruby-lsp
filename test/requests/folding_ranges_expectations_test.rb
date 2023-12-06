# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class FoldingRangesExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::FoldingRanges, "folding_ranges"

  def run_expectations(source)
    uri = URI("file://#{@_path}")
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::FoldingRanges.new(document.parse_result.comments, dispatcher)
    dispatcher.dispatch(document.tree)
    listener.response
  end
end
