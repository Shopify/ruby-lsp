# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class CodeActionResolveExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::CodeActionResolve, "code_action_resolve"

  def run_expectations(source)
    params = @__params&.any? ? @__params : default_args
    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    RubyLsp::Requests::CodeActionResolve.new(document, @global_state, params).perform
  end

  def assert_expectations(source, expected)
    actual = run_expectations(source)
    assert_equal(build_code_action(json_expectations(expected)), JSON.parse(actual.to_json))
  end

  def assert_match_to_expected(source, expected)
    actual = run_expectations(source)
    assert_equal(build_code_action(expected), JSON.parse(actual.to_json))
  end

  def test_toggle_block_do_end_to_brackets
    @__params = {
      kind: "refactor.rewrite",
      title: "Refactor: Toggle block style",
      data: {
        range: {
          start: { line: 0, character: 0 },
          end: { line: 2, character: 3 },
        },
        uri: "file:///fake",
      },
    }
    source = <<~RUBY
      [1, 2, 3].each do |number|
        puts number * 2
      end
    RUBY
    expected = {
      "title" => "Refactor: Toggle block style",
      "edit" => {
        "documentChanges" => [{
          "textDocument": {
            "uri": "file:///fake",
            "version": nil,
          },
          "edits" => [{
            "range" => {
              "start" => { "line" => 0, "character" => 15 },
              "end" => { "line" => 2, "character" => 3 },
            },
            "newText" => "{ |number| puts number * 2 }",
          }],
        }],
      },
    }
    assert_match_to_expected(source, expected)
  end

  def test_toggle_block_do_end_with_hash_to_brackets
    @__params = {
      kind: "refactor.rewrite",
      title: "Refactor: Toggle block style",
      data: {
        range: {
          start: { line: 0, character: 0 },
          end: { line: 5, character: 3 },
        },
        uri: "file:///fake",
      },
    }
    source = <<~RUBY
      arr.map do |a|
        {
          id: a.id,
          name: a.name
        }
      end
    RUBY
    expected = {
      "title" => "Refactor: Toggle block style",
      "edit" => {
        "documentChanges" => [{
          "textDocument": {
            "uri": "file:///fake",
            "version": nil,
          },
          "edits" => [{
            "range" => {
              "start" => { "line" => 0, "character" => 8 },
              "end" => { "line" => 5, "character" => 3 },
            },
            "newText" => "{ |a| { id: a.id, name: a.name } }",
          }],
        }],
      },
    }
    assert_match_to_expected(source, expected)
  end

  def test_toggle_block_do_end_with_hash_and_array_to_brackets
    @__params = {
      kind: "refactor.rewrite",
      title: "Refactor: Toggle block style",
      data: {
        range: {
          start: { line: 0, character: 0 },
          end: { line: 9, character: 3 },
        },
        uri: "file:///fake",
      },
    }
    source = <<~RUBY
      arr.map do |a|
        {
          id: a.id,
          name: a.name,
          items: [
            { value: a.value },
            { value: a.other_value }
          ]
        }
      end
    RUBY
    expected = {
      "title" => "Refactor: Toggle block style",
      "edit" => {
        "documentChanges" => [{
          "textDocument": {
            "uri": "file:///fake",
            "version": nil,
          },
          "edits" => [{
            "range" => {
              "start" => { "line" => 0, "character" => 8 },
              "end" => { "line" => 9, "character" => 3 },
            },
            "newText" => "{ |a| { id: a.id, name: a.name, items: [{ value: a.value }, { value: a.other_value }] } }",
          }],
        }],
      },
    }
    assert_match_to_expected(source, expected)
  end

  def test_toggle_block_do_end_with_multiple_params_and_nested_structures
    @__params = {
      kind: "refactor.rewrite",
      title: "Refactor: Toggle block style",
      data: {
        range: {
          start: { line: 0, character: 0 },
          end: { line: 3, character: 3 },
        },
        uri: "file:///fake",
      },
    }
    source = <<~RUBY
      [].each do |a, b, c|
        a = []
        { b: [a] }
      end
    RUBY
    expected = {
      "title" => "Refactor: Toggle block style",
      "edit" => {
        "documentChanges" => [{
          "textDocument" => {
            "uri" => "file:///fake",
            "version" => nil,
          },
          "edits" => [{
            "range" => {
              "start" => { "line" => 0, "character" => 8 },
              "end" => { "line" => 3, "character" => 3 },
            },
            "newText" => "{ |a, b, c| a = []; { b: [a] } }",
          }],
        }],
      },
    }
    assert_match_to_expected(source, expected)
  end

  def test_returns_error_when_selected_code_is_not_block_with_hash_and_array
    @__params = {
      kind: "refactor.rewrite",
      title: "Refactor: Toggle block style",
      data: {
        range: {
          start: { line: 0, character: 0 },
          end: { line: 0, character: 45 },
        },
        uri: "file:///fake",
      },
    }
    source = <<~RUBY
      { key1: [1, 2, 3], key2: { nested_key: "value" }}
    RUBY
    assert_equal(RubyLsp::Requests::CodeActionResolve::Error::InvalidTargetRange, run_expectations(source))
  end

  private

  def default_args
    {
      data: {
        range: {
          start: { line: 0, character: 1 },
          end: { line: 0, character: 2 },
        },
        uri: "file:///fake",
      },
    }
  end

  def build_code_action(expectation)
    result = LanguageServer::Protocol::Interface::CodeAction.new(
      title: expectation["title"],
      edit: LanguageServer::Protocol::Interface::WorkspaceEdit.new(
        document_changes: [
          LanguageServer::Protocol::Interface::TextDocumentEdit.new(
            text_document: LanguageServer::Protocol::Interface::OptionalVersionedTextDocumentIdentifier.new(
              uri: "file:///fake",
              version: nil,
            ),
            edits: build_text_edits(expectation.dig("edit", "documentChanges", 0, "edits") || []),
          ),
        ],
      ),
    )

    JSON.parse(result.to_json)
  end

  def build_text_edits(edits)
    edits.map do |edit|
      range = edit["range"]
      new_text = edit["newText"]
      LanguageServer::Protocol::Interface::TextEdit.new(
        range: LanguageServer::Protocol::Interface::Range.new(
          start: LanguageServer::Protocol::Interface::Position.new(
            line: range.dig("start", "line"), character: range.dig("start", "character"),
          ),
          end: LanguageServer::Protocol::Interface::Position.new(
            line: range.dig("end", "line"), character: range.dig("end", "character"),
          ),
        ),
        new_text: new_text,
      )
    end
  end
end
