# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class FoldingRangesExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::FoldingRanges, "folding_ranges"

  def run_expectations(source)
    uri = URI("file://#{@_path}")
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    parse_result = document.parse_result
    listener = RubyLsp::Requests::FoldingRanges.new(parse_result.comments, dispatcher)
    dispatcher.dispatch(parse_result.value)
    listener.perform
  end
end
