# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class CodeActionsExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::CodeActions, "code_actions"

  def run_expectations(source)
    params = @__params&.any? ? @__params : default_args
    document = RubyLsp::Document.new(source: source, version: 1, uri: URI("file:///fake"))
    result = T.let(nil, T.nilable(T::Array[LanguageServer::Protocol::Interface::CodeAction]))

    stdout, _ = capture_io do
      result = RubyLsp::Requests::CodeActions.new(
        document,
        params[:range],
        params[:context],
      ).run
    end

    assert_empty(stdout)
    result
  end

  def assert_expectations(source, expected)
    actual = run_expectations(source)
    assert_equal(map_actions(json_expectations(expected)), JSON.parse(actual.to_json))
  end

  private

  def default_args
    {
      range: {
        start: { line: 0, character: 0 }, end: { line: 1, character: 1 },
      },
      context: {
        diagnostics: [],
      },
    }
  end

  def map_actions(expectation)
    quickfixes = expectation
      .select { |action| action["kind"] == "quickfix" }
      .map { |action| code_action_for_diagnostic(action) }
    refactors = expectation
      .select { |action| action["kind"].start_with?("refactor") }
      .map { |action| code_action_for_refactor(action) }
    result = [*quickfixes, *refactors]

    JSON.parse(result.to_json)
  end

  def code_action_for_diagnostic(diagnostic)
    LanguageServer::Protocol::Interface::CodeAction.new(
      title: diagnostic["title"],
      kind: LanguageServer::Protocol::Constant::CodeActionKind::QUICK_FIX,
      edit: LanguageServer::Protocol::Interface::WorkspaceEdit.new(
        document_changes: [
          LanguageServer::Protocol::Interface::TextDocumentEdit.new(
            text_document: LanguageServer::Protocol::Interface::OptionalVersionedTextDocumentIdentifier.new(
              uri: "file:///fake",
              version: nil,
            ),
            edits: diagnostic["edit"]["documentChanges"].first["edits"],
          ),
        ],
      ),
      is_preferred: true,
    )
  end

  def code_action_for_refactor(refactor)
    LanguageServer::Protocol::Interface::CodeAction.new(
      title: refactor["title"],
      kind: LanguageServer::Protocol::Constant::CodeActionKind::REFACTOR_EXTRACT,
      data: {
        range: refactor.dig("data", "range"),
        uri: refactor.dig("data", "uri"),
      },
    )
  end
end
