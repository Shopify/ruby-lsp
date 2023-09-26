# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DocumentHighlightExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentHighlight, "document_highlight"

  def run_expectations(source)
    uri = URI("file://#{@_path}")
    params = @__params&.any? ? @__params : default_args
    document = RubyLsp::Document.new(source: source, version: 1, uri: uri)
    target, parent = document.locate_node(params.first)

    emitter = RubyLsp::EventEmitter.new

    listener = RubyLsp::Requests::DocumentHighlight.for(target, parent, emitter, @message_queue)
    emitter.visit(document.tree)
    listener.response
  end

  def default_args
    [{ character: 0, line: 0 }]
  end
end
