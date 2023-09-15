# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

module RubyLsp
  class CodeActionResolveExpectationsTest < ExpectationsTestRunner
    expectations_tests Requests::CodeActionResolve, "code_action_resolve"

    def run_expectations(source)
      params = @__params&.any? ? @__params : default_args
      document = Document.new(source: source, version: 1, uri: URI("file:///fake.rb"))

      Requests::CodeActionResolve.new(document, params).run
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
      result = Interface::CodeAction.new(
        title: expectation["title"],
        edit: Interface::WorkspaceEdit.new(
          document_changes: [
            Interface::TextDocumentEdit.new(
              text_document: Interface::OptionalVersionedTextDocumentIdentifier.new(
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
        Interface::TextEdit.new(
          range: Interface::Range.new(
            start: Interface::Position.new(
              line: range.dig("start", "line"), character: range.dig("start", "character"),
            ),
            end: Interface::Position.new(
              line: range.dig("end", "line"), character: range.dig("end", "character"),
            ),
          ),
          new_text: new_text,
        )
      end
    end
  end
end
