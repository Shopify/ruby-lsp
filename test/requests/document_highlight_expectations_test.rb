# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

module RubyLsp
  class DocumentHighlightExpectationsTest < ExpectationsTestRunner
    expectations_tests Requests::DocumentHighlight, "document_highlight"

    def run_expectations(source)
      uri = URI("file://#{@_path}")
      params = @__params&.any? ? @__params : default_args
      document = Document.new(source: source, version: 1, uri: uri)
      target, parent = document.locate_node(params.first)

      emitter = EventEmitter.new

      listener = Requests::DocumentHighlight.new(target, parent, emitter, @message_queue)
      emitter.visit(document.tree)
      listener.response
    end

    def default_args
      [{ character: 0, line: 0 }]
    end
  end
end
