# typed: true
# frozen_string_literal: true

require "test_helper"

class CodeActionsTest < Minitest::Test
  def test_code_actions
    actions = [
      title: "Autocorrect Layout/IndentationWidth",
      replacements: [
        {
          range: {
            start: { line: 3, character: 0 },
            end: { line: 3, character: 0 },
          },
          newText: "  ",
        },
      ],
    ]

    assert_code_actions(<<~RUBY, actions, (3..4))
      # frozen_string_literal: true

      def foo
      puts "Hello, world!"
      end
    RUBY
  end

  private

  def assert_code_actions(source, code_actions, range)
    document = RubyLsp::Document.new(source)
    result = nil

    stdout, _ = capture_io do
      result = RubyLsp::Requests::CodeActions.run("file://#{__FILE__}", document, range)
    end

    assert_empty(stdout)
    assert_equal(map_diagnostics(code_actions).to_json, result.to_json)
  end

  def map_diagnostics(diagnostics)
    diagnostics.map do |diagnostic|
      LanguageServer::Protocol::Interface::CodeAction.new(
        title: diagnostic[:title],
        kind: LanguageServer::Protocol::Constant::CodeActionKind::QUICK_FIX,
        edit: LanguageServer::Protocol::Interface::WorkspaceEdit.new(
          document_changes: [
            LanguageServer::Protocol::Interface::TextDocumentEdit.new(
              text_document: LanguageServer::Protocol::Interface::OptionalVersionedTextDocumentIdentifier.new(
                uri: "file://#{__FILE__}",
                version: nil
              ),
              edits: diagnostic[:replacements]
            ),
          ]
        ),
        is_preferred: true,
      )
    end
  end
end
