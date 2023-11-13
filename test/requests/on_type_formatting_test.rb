# typed: true
# frozen_string_literal: true

require "test_helper"

class OnTypeFormattingTest < Minitest::Test
  def test_adding_missing_ends
    document = RubyLsp::Document.new(source: +"", version: 1, uri: URI("file:///fake.rb"))

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "class Foo",
      }],
      version: 2,
    )
    document.parse

    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 1, character: 2 }, "\n").run
    expected_edits = [
      {
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } },
        newText: "\n",
      },
      {
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } },
        newText: "end",
      },
      {
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } },
        newText: "$0",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_adding_missing_curly_brace_in_string_interpolation
    document = RubyLsp::Document.new(source: +"", version: 1, uri: URI("file:///fake.rb"))

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "\"something#\{\"",
      }],
      version: 2,
    )
    document.parse

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
    document = RubyLsp::Document.new(source: +"", version: 1, uri: URI("file:///fake.rb"))

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "[].each do |",
      }],
      version: 2,
    )
    document.parse

    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 0, character: 12 }, "|").run
    expected_edits = [
      {
        range: { start: { line: 0, character: 12 }, end: { line: 0, character: 12 } },
        newText: "|",
      },
      {
        range: { start: { line: 0, character: 12 }, end: { line: 0, character: 12 } },
        newText: "$0",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_pipe_is_not_added_in_regular_or_pipe
    document = RubyLsp::Document.new(source: +"", version: 1, uri: URI("file:///fake.rb"))

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "|",
      }],
      version: 2,
    )
    document.parse

    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 0, character: 2 }, "|").run
    assert_empty(T.must(edits))
  end

  def test_pipe_is_removed_if_user_adds_manually_after_completion
    document = RubyLsp::Document.new(source: +"", version: 1, uri: URI("file:///fake.rb"))

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "[].each do |",
      }],
      version: 2,
    )
    document.parse

    document.push_edits(
      [{
        range: { start: { line: 0, character: 12 }, end: { line: 0, character: 12 } },
        text: "|",
      }],
      version: 3,
    )
    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 0, character: 12 }, "|").run
    expected_edits = [
      {
        range: { start: { line: 0, character: 12 }, end: { line: 0, character: 12 } },
        newText: "|",
      },
      {
        range: { start: { line: 0, character: 12 }, end: { line: 0, character: 12 } },
        newText: "$0",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
    assert_equal("[].each do ||", document.source)

    # Push the third pipe manually after the completion happened
    document.push_edits(
      [{
        range: { start: { line: 0, character: 13 }, end: { line: 0, character: 13 } },
        text: "|",
      }],
      version: 3,
    )

    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 0, character: 13 }, "|").run
    expected_edits = [
      {
        range: { start: { line: 0, character: 13 }, end: { line: 0, character: 14 } },
        newText: "",
      },
      {
        range: { start: { line: 0, character: 13 }, end: { line: 0, character: 13 } },
        newText: "$0",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_pipe_is_removed_if_user_adds_manually_after_block_argument
    document = RubyLsp::Document.new(source: +"", version: 1, uri: URI("file:///fake.rb"))

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "[].each do |elem|",
      }],
      version: 2,
    )
    document.parse

    document.push_edits(
      [{
        range: { start: { line: 0, character: 17 }, end: { line: 0, character: 17 } },
        text: "|",
      }],
      version: 3,
    )
    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 0, character: 17 }, "|").run
    expected_edits = [
      {
        range: { start: { line: 0, character: 17 }, end: { line: 0, character: 18 } },
        newText: "",
      },
      {
        range: { start: { line: 0, character: 17 }, end: { line: 0, character: 17 } },
        newText: "$0",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_comment_continuation
    document = RubyLsp::Document.new(source: +"", version: 1, uri: URI("file:///fake.rb"))

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "    #    something",
      }],
      version: 2,
    )
    document.parse

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

  def test_keyword_handling
    document = RubyLsp::Document.new(source: +"", version: 1, uri: URI("file:///fake.rb"))

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "\"def\"g\"",
      }],
      version: 2,
    )
    document.parse

    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 0, character: 5 }, "\n").run
    assert_empty(edits)
  end

  def test_comment_continuation_with_other_line_break_matches
    document = RubyLsp::Document.new(source: +"", version: 1, uri: URI("file:///fake.rb"))

    # If the current comment line has another word we match for, such as `while`, we still only want to complete the new
    # comment, but avoid adding an incorrect end to the comment's `while` word
    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "    #    while",
      }],
      version: 2,
    )
    document.parse

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

  def test_comment_continuation_when_inserting_new_line_in_the_middle
    document = RubyLsp::Document.new(source: +"", version: 1, uri: URI("file:///fake.rb"))

    # When inserting a new line between while and blah, the document will have a syntax error momentarily before we auto
    # insert the comment continuation. We must avoid accidentally trying to add an `end` token to `while` while the
    # syntax error exists
    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "# while blah blah",
      }],
      version: 2,
    )
    document.parse

    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 0, character: 7 }, "\n").run
    expected_edits = [
      {
        range: { start: { line: 0, character: 7 }, end: { line: 0, character: 7 } },
        newText: "# ",
      },
      {
        range: { start: { line: 0, character: 2 }, end: { line: 0, character: 2 } },
        newText: "$0",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_breaking_line_between_keyword_and_more_content
    document = RubyLsp::Document.new(source: +"", version: 1, uri: URI("file:///fake.rb"))

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "if something\n",
      }],
      version: 2,
    )
    document.parse

    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 1, character: 2 }, "\n").run
    expected_edits = [
      {
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } },
        newText: "\n",
      },
      {
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } },
        newText: "end",
      },
      {
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } },
        newText: "$0",
      },
    ]

    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_breaking_line_between_keyword_when_there_is_content_on_the_next_line
    document = RubyLsp::Document.new(source: +"", version: 1, uri: URI("file:///fake.rb"))

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "if something\n  other_thing",
      }],
      version: 2,
    )
    document.parse

    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 0, character: 2 }, "\n").run
    assert_empty(edits)
  end

  def test_breaking_line_immediately_after_keyword
    document = RubyLsp::Document.new(source: +"", version: 1, uri: URI("file:///fake.rb"))

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "  def\nfoo",
      }],
      version: 2,
    )
    document.parse

    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 1, character: 2 }, "\n").run
    expected_edits = [
      {
        range: { start: { line: 2, character: 2 }, end: { line: 2, character: 2 } },
        newText: "  end\n",
      },
      {
        range: { start: { line: 0, character: 6 }, end: { line: 0, character: 6 } },
        newText: "$0",
      },
    ]

    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_adding_heredoc_delimiter
    document = RubyLsp::Document.new(source: +"", version: 1, uri: URI("file:///fake.rb"))

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "str = <<~STR",
      }],
      version: 2,
    )
    document.parse

    edits = RubyLsp::Requests::OnTypeFormatting.new(document, { line: 1, character: 2 }, "\n").run
    expected_edits = [
      {
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } },
        newText: "\n",
      },
      {
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } },
        newText: "STR",
      },
      {
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } },
        newText: "$0",
      }
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end
end
