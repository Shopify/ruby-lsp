# frozen_string_literal: true

require "test_helper"

class SyntaxErrorDiagnosticTest < Minitest::Test
  def setup
    @diagnostic = RubyLsp::Requests::Support::SyntaxErrorDiagnostic.new(
      {
        range: { start: { line: 2, character: 1 }, end: { line: 2, character: 1 } },
        text: " ",
      }
    )
  end

  def test_correctable
    refute_predicate(@diagnostic, :correctable?)
  end

  def test_to_lsp_diagnostic
    expected = LanguageServer::Protocol::Interface::Diagnostic.new(
      message: "Syntax error",
      source: "SyntaxTree",
      severity: LanguageServer::Protocol::Constant::DiagnosticSeverity::ERROR,
      range: { start: { line: 2, character: 1 }, end: { line: 2, character: 1 } }
    )

    assert_equal(expected.to_json, @diagnostic.to_lsp_diagnostic.to_json)
  end
end
