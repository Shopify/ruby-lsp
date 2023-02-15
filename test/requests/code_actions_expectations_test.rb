# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class CodeActionsExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::CodeActions, "code_actions"

  def run_expectations(source)
    params = @__params&.any? ? @__params : default_args
    document = RubyLsp::Document.new(source)
    result = T.let(nil, T.nilable(T::Array[LanguageServer::Protocol::Interface::CodeAction]))

    stdout, _ = capture_io do
      result = RubyLsp::Requests::CodeActions.new(
        "file://#{__FILE__}",
        document,
        params[:start]..params[:end],
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
    { start: 0, end: 1, context: { diagnostics: [] } }
  end

  def map_actions(diagnostics)
    response = diagnostics.map do |diagnostic|
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

    JSON.parse(response.to_json)
  end
end
