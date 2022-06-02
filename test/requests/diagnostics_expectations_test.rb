# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DiagnosticsExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Diagnostics, "diagnostics"

  def run_expectations(source)
    document = RubyLsp::Document.new(source)
    RubyLsp::Requests::Diagnostics.run("file://#{__FILE__}", document)
  end

  def assert_expectations(source, expected)
    result = nil

    stdout, _ = capture_io do
      result = run_expectations(source)
    end

    assert_empty(stdout)

    diagnostics = json_expectations(expected)
    assert_equal(map_diagnostics(diagnostics).to_json, result.map(&:to_lsp_diagnostic).to_json)
  end

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
    end
  end
end
