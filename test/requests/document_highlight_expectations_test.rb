# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DocumentHighlightExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentHighlight, "document_highlight"

  def run_expectations(source)
    uri = URI("file://#{@_path}")
    params = @__params&.any? ? @__params : default_args
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::DocumentHighlight.new(document, params.first, dispatcher)
    dispatcher.dispatch(document.tree)
    listener.response
  end

  def default_args
    [{ character: 0, line: 0 }]
  end
end
