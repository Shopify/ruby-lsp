# typed: true
# frozen_string_literal: true

require "test_helper"

class DiagnosticsTest < Minitest::Test
  def test_empty_diagnostics_for_ignored_file
    fixture_path = File.expand_path("../fixtures/def_multiline_params.rb", __dir__)
    document = RubyLsp::Document.new(File.read(fixture_path))

    result = RubyLsp::Requests::Diagnostics.new("file://#{fixture_path}", document).run
    assert_empty(result)
  end

  def test_returns_nil_if_document_is_not_in_project_folder
    document = RubyLsp::Document.new(<<~RUBY)
      def foo
      wrong_indent
      end
    RUBY

    assert_nil(RubyLsp::Requests::Diagnostics.new("file:///some/other/folder/file.rb", document).run)
  end

  private

  def syntax_error_diagnostics(edits)
    edits.map do |edit|
      LanguageServer::Protocol::Interface::Diagnostic.new(
        message: "Syntax error",
        source: "SyntaxTree",
        severity: LanguageServer::Protocol::Constant::DiagnosticSeverity::ERROR,
        range: edit[:range],
      )
    end
  end
end
