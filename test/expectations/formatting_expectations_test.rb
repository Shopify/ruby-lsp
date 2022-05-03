# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class FormattingExpectationsTest < ExpectationsTestRunner
  def run_expectations(source)
    document = RubyLsp::Document.new(source)
    RubyLsp::Requests::Formatting.run("file://#{__FILE__}", document).first.new_text
  end

  def assert_expectations(source, expected)
    result = nil

    stdout, _ = capture_io do
      result = run_expectations(source)
    end

    assert_empty(stdout)
    assert_equal(expected, result)
  end

  expectations_tests RubyLsp::Requests::Formatting, File.basename(__dir__)
end
