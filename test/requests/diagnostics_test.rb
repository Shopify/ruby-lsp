# frozen_string_literal: true

require "test_helper"

class DiagnosticsTest < Minitest::Test
  def test_syntax_error_diagnostics
    document = RubyLsp::Document.new(+<<~RUBY)
      class Foo
      end
    RUBY

    error_edit = {
      range: { start: { line: 0, character: 10 }, end: { line: 0, character: 10 } },
      text: "\n  end",
    }

    document.push_edits([error_edit])

    result = RubyLsp::Requests::Diagnostics.run("file://#{__FILE__}", document)
    assert_equal(syntax_error_diagnostics([error_edit]).to_json, result.map(&:to_lsp_diagnostic).to_json)
  end

  private

  def syntax_error_diagnostics(edits)
    edits.map do |edit|
      LanguageServer::Protocol::Interface::Diagnostic.new(
        message: "Syntax error",
        source: "SyntaxTree",
        severity: LanguageServer::Protocol::Constant::DiagnosticSeverity::ERROR,
        range: edit[:range]
      )
    end
  end
end
