# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class DocumentHighlightExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentHighlight, "document_highlight"

  def run_expectations(source)
    uri = URI("file://#{@_path}")
    params = @__params&.any? ? @__params : default_args
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri)

    global_state = RubyLsp::GlobalState.new
    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::DocumentHighlight.new(global_state, document, params.first, dispatcher)
    dispatcher.dispatch(document.parse_result.value)
    listener.perform
  end

  def default_args
    [{ character: 0, line: 0 }]
  end
end
