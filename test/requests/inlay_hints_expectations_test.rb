# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

module RubyLsp
  class InlayHintsExpectationsTest < ExpectationsTestRunner
    expectations_tests Requests::InlayHints, "inlay_hints"

    def run_expectations(source)
      message_queue = Thread::Queue.new
      params = @__params&.any? ? @__params : default_args
      uri = URI("file://#{@_path}")
      document = Document.new(source: source, version: 1, uri: uri)

      emitter = EventEmitter.new
      listener = Requests::InlayHints.new(params.first, emitter, message_queue)
      emitter.visit(document.tree)
      listener.response
    ensure
      T.must(message_queue).close
    end

    def default_args
      [0..20]
    end
  end
end
