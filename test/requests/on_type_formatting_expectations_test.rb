# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class OnTypeFormattingExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::OnTypeFormatting, "on_type_formatting"

  def run_expectations(source)
    document = RubyLsp::Document.new(source)
    params = @__params&.any? ? @__params : default_args
    T.unsafe(RubyLsp::Requests::OnTypeFormatting).new(document, *params).run
  end

  def default_args
    [{ line: 1, character: 0 }, "\n"]
  end
end
