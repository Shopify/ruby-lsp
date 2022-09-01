# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class FormattingExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Formatting, "formatting"

  def run_expectations(path)
    source = File.read(path)
    document = RubyLsp::Document.new(source)
    # because we exclude fixture files in rubocop.yml, rubocop will ignore the file if we use the real fixture uri
    RubyLsp::Requests::Formatting.new("file://#{__FILE__}", document).run&.first&.new_text
  end

  def assert_expectations(path, expected)
    result = T.let(nil, T.nilable(T::Array[LanguageServer::Protocol::Interface::TextEdit]))

    stdout, _ = capture_io do
      result = run_expectations(path)
    end

    assert_empty(stdout)
    assert_equal(expected, result)
  end

  def initialize_params(_expected)
  end
end
