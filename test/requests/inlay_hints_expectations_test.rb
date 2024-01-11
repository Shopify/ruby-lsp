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
    hints_configuration = RubyLsp::RequestConfig.new({ implicitRescue: true, implicitHashValue: true })
    request = RubyLsp::Requests::InlayHints.new(document, params.first, hints_configuration, dispatcher)
    dispatcher.dispatch(document.tree)
    request.perform
  end

  def default_args
    [{ start: { line: 0, character: 0 }, end: { line: 20, character: 20 } }]
  end

  def test_skip_implicit_hash_value
    uri = URI("file://foo.rb")
    document = RubyLsp::RubyDocument.new(uri: uri, source: <<~RUBY, version: 1)
      {bar:, baz:}
    RUBY

    dispatcher = Prism::Dispatcher.new
    hints_configuration = RubyLsp::RequestConfig.new({ implicitRescue: true, implicitHashValue: false })
    request = RubyLsp::Requests::InlayHints.new(document, default_args.first, hints_configuration, dispatcher)
    dispatcher.dispatch(document.tree)
    request.perform
  end

  def test_skip_implicit_rescue
    uri = URI("file://foo.rb")
    document = RubyLsp::RubyDocument.new(uri: uri, source: <<~RUBY, version: 1)
      begin
      rescue
      end
    RUBY

    dispatcher = Prism::Dispatcher.new
    hints_configuration = RubyLsp::RequestConfig.new({ implicitRescue: false, implicitHashValue: true })
    request = RubyLsp::Requests::InlayHints.new(document, default_args.first, hints_configuration, dispatcher)
    dispatcher.dispatch(document.tree)
    assert_empty(request.perform)
  end
end
