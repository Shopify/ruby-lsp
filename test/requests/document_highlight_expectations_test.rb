# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DocumentHighlightExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentHighlight, "document_highlight"

  def default_args
    [{ character: 0, line: 0 }]
  end
end
