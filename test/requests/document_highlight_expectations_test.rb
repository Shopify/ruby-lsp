# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DocumentHighlightExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentHighlight, "document_highlight"

  def test_when_document_is_not_parsed
    broken_source = "class Foo"
    document = RubyLsp::Document.new(source: broken_source, version: 1, uri: "file:///fake.rb")
    result = RubyLsp::Requests::DocumentHighlight.new(document, { line: 0, character: 0 }).run
    assert_empty(result)
  end

  def default_args
    [{ character: 0, line: 0 }]
  end
end
