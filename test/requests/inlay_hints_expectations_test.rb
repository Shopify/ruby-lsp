# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class InlayHintsExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::InlayHints, "inlay_hints"

  def run_expectations(source)
    params = @__params&.any? ? @__params : default_args
    uri = URI("file://#{@_path}")
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::InlayHints.new(params.first, dispatcher)
    dispatcher.dispatch(document.tree)
    listener.response
  end

  def default_args
    [0..20]
  end
end
