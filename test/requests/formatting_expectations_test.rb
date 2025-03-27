# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class FormattingExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Formatting, "formatting"

  def run_expectations(source)
    @global_state.formatter = "rubocop_internal"
    @global_state.register_formatter(
      "rubocop_internal",
      RubyLsp::Requests::Support::RuboCopFormatter.new,
    )
    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI::Generic.from_path(path: __FILE__),
      global_state: @global_state,
    )
    RubyLsp::Requests::Formatting.new(@global_state, document).perform&.first&.new_text
  end

  def assert_expectations(source, expected)
    result = nil #: Array[LanguageServer::Protocol::Interface::TextEdit]?

    stdout, _ = capture_io do
      result = run_expectations(source)
    end

    assert_empty(stdout)
    assert_equal(expected, result)
  end

  def initialize_params(_expected)
  end
end
