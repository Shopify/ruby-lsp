# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class FormattingExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Formatting, "formatting"

  def run_expectations(source)
    document = RubyLsp::Document.new(source: source, version: 1, uri: "file://#{__FILE__}")
    RubyLsp::Requests::Formatting.new(document).run&.first&.new_text
  end

  def assert_expectations(source, expected)
    result = T.let(nil, T.nilable(T::Array[LanguageServer::Protocol::Interface::TextEdit]))

    stdout, _ = capture_io do
      result = run_expectations(source)
    end

    assert_empty(stdout)
    assert_equal(expected, result)
  end

  def initialize_params(_expected)
  end
end
