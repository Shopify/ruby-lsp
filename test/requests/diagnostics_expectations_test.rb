# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class DiagnosticsExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Diagnostics, "diagnostics"

  def run_expectations(source)
    result = nil #: Array[RubyLsp::Interface::Diagnostic]?
    @global_state.apply_options({
      initializationOptions: { linters: ["rubocop_internal"] },
    })
    @global_state.register_formatter(
      "rubocop_internal",
      RubyLsp::Requests::Support::RuboCopFormatter.new,
    )

    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI::Generic.from_path(path: File.expand_path(__FILE__)),
      global_state: @global_state,
    )

    stdout, _ = capture_io do
      result = RubyLsp::Requests::Diagnostics.new(@global_state, document)
        .perform #: as Array[RubyLsp::Interface::Diagnostic]
    end

    assert_empty(stdout)

    # On Windows, RuboCop will complain that the file is missing a carriage return at the end. We need to ignore these
    result&.reject { |diagnostic| diagnostic.source == "RuboCop" && diagnostic.code == "Layout/EndOfLine" }
  rescue RubyLsp::Requests::Support::InternalRuboCopError
    skip("Fixture requires a fix from Rubocop")
  end

  def assert_expectations(source, expected)
    actual = run_expectations(source) #: Array[LanguageServer::Protocol::Interface::Diagnostic]

    # Sanitize the URI keys so that it matches file:///fake and not a real path in the user machine
    actual.each do |diagnostic|
      attributes = diagnostic.attributes

      attributes.fetch(:data, {}).fetch(:code_actions, []).each do |code_action|
        code_action_changes = code_action.attributes[:edit].attributes[:documentChanges]
        code_action_changes.each do |code_action_change|
          code_action_change
            .attributes[:textDocument]
            .instance_variable_set(:@attributes, { uri: "file:///fake", version: nil })
        end
      end
    end

    assert_equal(JSON.parse(map_diagnostics(json_expectations(expected))), JSON.parse(actual.to_json))
  end

  private

  def map_diagnostics(diagnostics)
    diagnostics.map do |diagnostic|
      LanguageServer::Protocol::Interface::Diagnostic.new(
        message: diagnostic["message"],
        source: diagnostic["source"],
        code: diagnostic["code"],
        severity: diagnostic["severity"],
        code_description: diagnostic["codeDescription"],
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
