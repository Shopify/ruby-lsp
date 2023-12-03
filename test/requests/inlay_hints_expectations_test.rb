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
    hints_configuration = { implicitRescue: true, implicitHashValue: true }
    listener = RubyLsp::Requests::InlayHints.new(params.first, hints_configuration, dispatcher)
    dispatcher.dispatch(document.tree)
    listener.response
  end

  def default_args
    [0..20]
  end

  def test_skip_implicit_hash_value
    uri = URI("file://foo.rb")
    document = RubyLsp::RubyDocument.new(uri: uri, source: <<~RUBY, version: 1)
      {bar:, baz:}
    RUBY

    dispatcher = Prism::Dispatcher.new
    hints_configuration = { implicitRescue: true, implicitHashValue: false }
    listener = RubyLsp::Requests::InlayHints.new(default_args.first, hints_configuration, dispatcher)
    dispatcher.dispatch(document.tree)
    assert_empty(listener.response)
  end

  def test_skip_implicit_rescue
    uri = URI("file://foo.rb")
    document = RubyLsp::RubyDocument.new(uri: uri, source: <<~RUBY, version: 1)
      begin
      rescue
      end
    RUBY

    dispatcher = Prism::Dispatcher.new
    hints_configuration = { implicitRescue: false, implicitHashValue: true }
    listener = RubyLsp::Requests::InlayHints.new(default_args.first, hints_configuration, dispatcher)
    dispatcher.dispatch(document.tree)
    assert_empty(listener.response)
  end
end
