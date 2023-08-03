# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DiagnosticsExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Diagnostics, "diagnostics"

  def run_expectations(source)
    if RUBY_PLATFORM.match?(/(mswin|mingw)/) &&
        (@_path == "test/fixtures/if_inside_else.rb" || @_path == "test/fixtures/def_bad_formatting.rb")
      skip("Skipping on Windows: https://github.com/Shopify/ruby-lsp/issues/751")
    end

    document = RubyLsp::Document.new(source: source, version: 1, uri: URI("file://#{__FILE__}"))
    RubyLsp::Requests::Diagnostics.new(document).run
    result = T.let(nil, T.nilable(T::Array[RubyLsp::Requests::Support::RuboCopDiagnostic]))

    stdout, _ = capture_io do
      result = T.cast(
        RubyLsp::Requests::Diagnostics.new(document).run,
        T::Array[RubyLsp::Requests::Support::RuboCopDiagnostic],
      )
    end

    assert_empty(stdout)
    T.must(result).map(&:to_lsp_diagnostic)
  end

  def assert_expectations(source, expected)
    actual = T.let(run_expectations(source), T::Array[LanguageServer::Protocol::Interface::Diagnostic])

    # Sanitize the URI keys so that it matches file:///fake and not a real path in the user machine
    actual.each do |diagnostic|
      attributes = diagnostic.attributes

      text_document_identifier = attributes[:data][:code_action]
        .attributes[:edit]
        .attributes[:documentChanges][0]
        .attributes[:textDocument]

      text_document_identifier.instance_variable_set(:@attributes, { uri: "file:///fake", version: nil })
    end

    assert_equal(JSON.parse(map_diagnostics(json_expectations(expected))), JSON.parse(actual.to_json))
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
            character: diagnostic["range"]["start"]["character"],
          ),
          end: LanguageServer::Protocol::Interface::Position.new(
            line: diagnostic["range"]["end"]["line"],
            character: diagnostic["range"]["end"]["character"],
          ),
        ),
        data: diagnostic["data"],
      )
    end.to_json
  end
end
