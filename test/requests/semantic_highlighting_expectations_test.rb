# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class SemanticHighlightingExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::SemanticHighlighting, "semantic_highlighting"

  def run_expectations(path)
    source = File.read(path)
    document = RubyLsp::Document.new(source)
    RubyLsp::Requests::SemanticHighlighting.new(
      document,
      encoder: RubyLsp::Requests::Support::SemanticTokenEncoder.new
    ).run
  end

  def assert_expectations(path, expected)
    actual = run_expectations(path).data
    assert_equal(json_expectations(expected).to_json, decode_tokens(actual).to_json)
  end

  private

  def decode_tokens(array)
    tokens = []
    array.each_slice(5) do |token|
      tokens << {
        delta_line: token[0],
        delta_start_char: token[1],
        length: token[2],
        token_type: token[3],
        token_modifiers: token[4],
      }
    end
    tokens
  end
end
