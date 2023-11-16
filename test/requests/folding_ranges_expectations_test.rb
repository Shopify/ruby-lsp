# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class FoldingRangesExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::FoldingRanges, "folding_ranges"

  def run_expectations(source)
    message_queue = Thread::Queue.new
    uri = URI("file://#{@_path}")
    document = RubyLsp::Document.new(source: source, version: 1, uri: uri)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::FoldingRanges.new(document.parse_result.comments, dispatcher, message_queue)
    dispatcher.dispatch(document.tree)
    listener.response
  ensure
    T.must(message_queue).close
  end
end
