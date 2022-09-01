# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DiagnosticsExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Diagnostics, "diagnostics"

  def run_expectations(path)
    # because we exclude fixture files in rubocop.yml, rubocop will ignore the file if we use the real fixture uri
    uri = "file://#{__FILE__}"
    source = File.read(path)
    document = RubyLsp::Document.new(source)
    RubyLsp::Requests::Diagnostics.new(uri, document).run
    result = T.let(nil, T.nilable(T::Array[RubyLsp::Requests::Support::RuboCopDiagnostic]))

    stdout, _ = capture_io do
      result = T.cast(
        RubyLsp::Requests::Diagnostics.new(uri, document).run,
        T::Array[RubyLsp::Requests::Support::RuboCopDiagnostic]
      )
    end

    assert_empty(stdout)
    T.must(result).map(&:to_lsp_diagnostic).to_json
  end

  def assert_expectations(path, expected)
    actual = run_expectations(path)
    assert_equal(map_diagnostics(json_expectations(expected)), JSON.parse(actual.to_json))
  end

  private

  def map_diagnostics(diagnostics)
    diagnostics.map do |diagnostic|
      LanguageServer::Protocol::Interface::Diagnostic.new(
        message: diagnostic["message"],
        source: "RuboCop",
        code: diagnostic["code"],
        severity: diagnostic["severity"],
        range: LanguageServer::Protocol::Interface::Range.new(
          start: LanguageServer::Protocol::Interface::Position.new(
            line: diagnostic["range"]["start"]["line"],
            character: diagnostic["range"]["start"]["character"]
          ),
          end: LanguageServer::Protocol::Interface::Position.new(
            line: diagnostic["range"]["end"]["line"],
            character: diagnostic["range"]["end"]["character"]
          )
        )
      )
    end.to_json
  end
end
