# frozen_string_literal: true

require "test_helper"

class DiagnosticsTest < Minitest::Test
  def test_diagnostics
    diagnostics = [
      start: { line: 3, character: 0 },
      end: { line: 3, character: 0 },
      severity: :info,
      code: "Layout/IndentationWidth",
      message: "Layout/IndentationWidth: Use 2 (not 0) spaces for indentation.",
    ]

    assert_diagnostics(<<~RUBY, diagnostics)
      # frozen_string_literal: true

      def foo
      puts "Hello, world!"
      end
    RUBY
  end

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

  def assert_diagnostics(source, diagnostics)
    document = RubyLsp::Document.new(source)
    result = nil

    stdout, _ = capture_io do
      result = RubyLsp::Requests::Diagnostics.run("file://#{__FILE__}", document)
    end

    assert_empty(stdout)
    assert_equal(map_diagnostics(diagnostics).to_json, result.map(&:to_lsp_diagnostic).to_json)
  end

  def map_diagnostics(diagnostics)
    diagnostics.map do |diagnostic|
      LanguageServer::Protocol::Interface::Diagnostic.new(
        message: diagnostic[:message],
        source: "RuboCop",
        code: diagnostic[:code],
        severity: RubyLsp::Requests::Support::RuboCopDiagnostic::RUBOCOP_TO_LSP_SEVERITY[diagnostic[:severity]],
        range: LanguageServer::Protocol::Interface::Range.new(
          start: LanguageServer::Protocol::Interface::Position.new(
            line: diagnostic[:start][:line],
            character: diagnostic[:start][:character]
          ),
          end: LanguageServer::Protocol::Interface::Position.new(
            line: diagnostic[:end][:line],
            character: diagnostic[:end][:character]
          )
        )
      )
    end
  end

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
