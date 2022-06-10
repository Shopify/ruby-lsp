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
      result = T.unsafe(RubyLsp::Requests::CodeActions).new(
        "file://#{__FILE__}",
        document,
        params[:start]..params[:end]
      ).run
    end

    assert_empty(stdout)

    # RuboCop needs a real URI to work, but we can't put that in an expectation file since it changes between each
    # developer's machine. To workaround it, we run using a real URI and then force set the result URIs to a fake one
    T.must(result).each do |action|
      action.attributes[:edit].attributes[:documentChanges].each do |changes|
        changes.attributes[:textDocument].instance_variable_set(:@attributes, { uri: "file:///fake", version: nil })
      end
    end

    result
  end

  private

  def default_args
    { start: 0, end: 1 }
  end

  def map_result(diagnostics)
    response = diagnostics.map do |diagnostic|
      LanguageServer::Protocol::Interface::CodeAction.new(
        title: diagnostic["title"],
        kind: LanguageServer::Protocol::Constant::CodeActionKind::QUICK_FIX,
        edit: LanguageServer::Protocol::Interface::WorkspaceEdit.new(
          document_changes: [
            LanguageServer::Protocol::Interface::TextDocumentEdit.new(
              text_document: LanguageServer::Protocol::Interface::OptionalVersionedTextDocumentIdentifier.new(
                uri: "file:///fake",
                version: nil
              ),
              edits: diagnostic["edit"]["documentChanges"].first["edits"]
            ),
          ]
        ),
        is_preferred: true,
      )
    end

    JSON.parse(response.to_json)
  end
end
