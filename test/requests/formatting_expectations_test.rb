# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

module RubyLsp
  class FormattingExpectationsTest < ExpectationsTestRunner
    expectations_tests Requests::Formatting, "formatting"

    def run_expectations(source)
      document = Document.new(source: source, version: 1, uri: URI::Generic.from_path(path: __FILE__))
      Requests::Formatting.new(document, formatter: "rubocop").run&.first&.new_text
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
end
