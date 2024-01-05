# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class CodeActionResolveExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::CodeActionResolve, "code_action_resolve"

  def run_expectations(source)
    params = @__params&.any? ? @__params : default_args
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: URI("file:///fake.rb"))

    RubyLsp::Requests::CodeActionResolve.new(document, params).response
  end

  def assert_expectations(source, expected)
    actual = run_expectations(source)
    assert_equal(build_code_action(json_expectations(expected)), JSON.parse(actual.to_json))
  end

  private

  def default_args
    {
      data: {
        range: {
          start: { line: 0, character: 1 },
          end: { line: 0, character: 2 },
        },
        uri: "file:///fake",
      },
    }
  end

  def build_code_action(expectation)
    result = LanguageServer::Protocol::Interface::CodeAction.new(
      title: expectation["title"],
      edit: LanguageServer::Protocol::Interface::WorkspaceEdit.new(
        document_changes: [
          LanguageServer::Protocol::Interface::TextDocumentEdit.new(
            text_document: LanguageServer::Protocol::Interface::OptionalVersionedTextDocumentIdentifier.new(
              uri: "file:///fake",
              version: nil,
            ),
            edits: build_text_edits(expectation.dig("edit", "documentChanges", 0, "edits") || []),
          ),
        ],
      ),
    )

    JSON.parse(result.to_json)
  end

  def build_text_edits(edits)
    edits.map do |edit|
      range = edit["range"]
      new_text = edit["newText"]
      LanguageServer::Protocol::Interface::TextEdit.new(
        range: LanguageServer::Protocol::Interface::Range.new(
          start: LanguageServer::Protocol::Interface::Position.new(
            line: range.dig("start", "line"), character: range.dig("start", "character"),
          ),
          end: LanguageServer::Protocol::Interface::Position.new(
            line: range.dig("end", "line"), character: range.dig("end", "character"),
          ),
        ),
        new_text: new_text,
      )
    end
  end
end
