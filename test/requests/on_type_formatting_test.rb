# typed: true
# frozen_string_literal: true

require "test_helper"

class OnTypeFormattingTest < Minitest::Test
  def test_adding_missing_ends
    document = RubyLsp::Document.new(+"")

    document.push_edits([{
      range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
      text: "class Foo\n",
    }])

    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 0, character: 8 }, "\n").run
    expected_edits = [
      {
        range: { start: { line: 0, character: 8 }, end: { line: 0, character: 8 } },
        newText: " \nend",
      },
      {
        range: { start: { line: 0, character: 2 }, end: { line: 0, character: 2 } },
        newText: "$0",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_adding_missing_curly_brace_in_string_interpolation
    document = RubyLsp::Document.new(+"")

    document.push_edits([{
      range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
      text: "\"something#\{\"",
    }])

    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 0, character: 11 }, "{").run
    expected_edits = [
      {
        range: { start: { line: 0, character: 11 }, end: { line: 0, character: 11 } },
        newText: "}",
      },
      {
        range: { start: { line: 0, character: 11 }, end: { line: 0, character: 11 } },
        newText: "$0",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_adding_missing_pipe
    document = RubyLsp::Document.new(+"")

    document.push_edits([{
      range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
      text: "[].each do |",
    }])

    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 0, character: 11 }, "|").run
    expected_edits = [
      {
        range: { start: { line: 0, character: 11 }, end: { line: 0, character: 11 } },
        newText: "|",
      },
      {
        range: { start: { line: 0, character: 11 }, end: { line: 0, character: 11 } },
        newText: "$0",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_pipe_is_not_added_in_regular_or_pipe
    document = RubyLsp::Document.new(+"")

    document.push_edits([{
      range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
      text: "|",
    }])

    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 0, character: 11 }, "|").run
    assert_empty(T.must(edits))
  end

  def test_comment_continuation
    document = RubyLsp::Document.new(+"")

    document.push_edits([{
      range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
      text: "    #    something",
    }])

    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 0, character: 14 }, "\n").run
    expected_edits = [
      {
        range: { start: { line: 0, character: 14 }, end: { line: 0, character: 14 } },
        newText: "#    ",
      },
      {
        range: { start: { line: 0, character: 9 }, end: { line: 0, character: 9 } },
        newText: "$0",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end
end
