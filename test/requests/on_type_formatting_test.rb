# typed: true
# frozen_string_literal: true

require "test_helper"

class OnTypeFormattingTest < Minitest::Test
  def setup
    @global_state = RubyLsp::GlobalState.new
  end

  def test_adding_missing_ends
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "class Foo",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 1, character: 2 },
      "\n",
      "Visual Studio Code",
    ).perform
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
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "\"something#\{\"",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 0, character: 11 },
      "{",
      "Visual Studio Code",
    ).perform
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
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "[].each do |",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 0, character: 12 },
      "|",
      "Visual Studio Code",
    ).perform
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
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "|",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 0, character: 2 },
      "|",
      "Visual Studio Code",
    ).perform
    assert_empty(T.must(edits))
  end

  def test_pipe_is_removed_if_user_adds_manually_after_completion
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "[].each do |",
      }],
      version: 2,
    )
    document.parse!

    document.push_edits(
      [{
        range: { start: { line: 0, character: 12 }, end: { line: 0, character: 12 } },
        text: "|",
      }],
      version: 3,
    )
    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 0, character: 12 },
      "|",
      "Visual Studio Code",
    ).perform
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

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 0, character: 13 },
      "|",
      "Visual Studio Code",
    ).perform
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
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "[].each do |elem|",
      }],
      version: 2,
    )
    document.parse!

    document.push_edits(
      [{
        range: { start: { line: 0, character: 17 }, end: { line: 0, character: 17 } },
        text: "|",
      }],
      version: 3,
    )
    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 0, character: 17 },
      "|",
      "Visual Studio Code",
    ).perform
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
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "    #    something",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 0, character: 14 },
      "\n",
      "Visual Studio Code",
    ).perform
    expected_edits = [
      {
        range: { start: { line: 0, character: 14 }, end: { line: 0, character: 14 } },
        newText: "#    ",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_comment_continuation_does_not_apply_to_rbs_signatures
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "    #: (String) -> String",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 0, character: 14 },
      "\n",
      "Visual Studio Code",
    ).perform
    assert_empty(edits)
  end

  def test_comment_continuation_does_not_apply_to_trailing_rbs_signature
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "attr_reader :name #: String",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 0, character: 14 },
      "\n",
      "Visual Studio Code",
    ).perform
    assert_empty(edits)
  end

  def test_keyword_handling
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "\"def\"g\"",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 0, character: 5 },
      "\n",
      "Visual Studio Code",
    ).perform
    assert_empty(edits)
  end

  def test_comment_continuation_with_other_line_break_matches
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    # If the current comment line has another word we match for, such as `while`, we still only want to complete the new
    # comment, but avoid adding an incorrect end to the comment's `while` word
    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "    #    while",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 0, character: 14 },
      "\n",
      "Visual Studio Code",
    ).perform
    expected_edits = [
      {
        range: { start: { line: 0, character: 14 }, end: { line: 0, character: 14 } },
        newText: "#    ",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_comment_continuation_when_inserting_new_line_in_the_middle
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

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
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 0, character: 7 },
      "\n",
      "Visual Studio Code",
    ).perform
    expected_edits = [
      {
        range: { start: { line: 0, character: 7 }, end: { line: 0, character: 7 } },
        newText: "# ",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_breaking_line_between_keyword_and_more_content
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "if something\n",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 1, character: 2 },
      "\n",
      "Visual Studio Code",
    ).perform
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
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "if something\n  other_thing",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 0, character: 2 },
      "\n",
      "Visual Studio Code",
    ).perform
    assert_empty(edits)
  end

  def test_breaking_line_immediately_after_keyword
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "  def\nfoo",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 1, character: 2 },
      "\n",
      "Visual Studio Code",
    ).perform
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

  def test_auto_indent_after_end_keyword
    document = RubyLsp::RubyDocument.new(
      source: +"if foo\nbar\nend",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )
    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 2, character: 2 },
      "d",
      "Visual Studio Code",
    ).perform

    expected_edits = [
      {
        range: { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } },
        newText: "  ",
      },
      {
        range: { start: { line: 2, character: 2 }, end: { line: 2, character: 2 } },
        newText: "$0",
      },
    ]

    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_auto_indent_after_end_keyword_with_complex_body
    document = RubyLsp::RubyDocument.new(
      source: +"if foo\nif bar\n  baz\nend\nend",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )
    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 4, character: 2 },
      "d",
      "Visual Studio Code",
    ).perform

    expected_edits = [
      {
        range: { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } },
        newText: "  ",
      },
      {
        range: { start: { line: 2, character: 0 }, end: { line: 2, character: 0 } },
        newText: "  ",
      },
      {
        range: { start: { line: 3, character: 0 }, end: { line: 3, character: 0 } },
        newText: "  ",
      },
      {
        range: { start: { line: 4, character: 2 }, end: { line: 4, character: 2 } },
        newText: "$0",
      },
    ]

    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_auto_indent_after_end_keyword_does_not_add_extra_indentation
    document = RubyLsp::RubyDocument.new(
      source: +"if foo\n  bar\nend",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )
    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 2, character: 2 },
      "d",
      "Visual Studio Code",
    ).perform

    expected_edits = [
      {
        range: { start: { line: 2, character: 2 }, end: { line: 2, character: 2 } },
        newText: "$0",
      },
    ]

    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_breaking_line_if_a_keyword_is_part_of_method_call
    document = RubyLsp::RubyDocument.new(
      source: +"  force({",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )
    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 1, character: 2 },
      "\n",
      "Visual Studio Code",
    ).perform
    assert_empty(edits)
  end

  def test_breaking_line_if_a_keyword_in_a_subexpression
    document = RubyLsp::RubyDocument.new(
      source: +"  var = (if",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )
    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 1, character: 2 },
      "\n",
      "Visual Studio Code",
    ).perform
    expected_edits = [
      {
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } },
        newText: "\n",
      },
      {
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } },
        newText: "  end",
      },
      {
        range: { start: { line: 1, character: 4 }, end: { line: 1, character: 4 } },
        newText: "$0",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_adding_heredoc_delimiter
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "str = <<~STR",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 1, character: 2 },
      "\n",
      "Visual Studio Code",
    ).perform
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
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_plain_heredoc_completion
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "str = <<STR",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 1, character: 2 },
      "\n",
      "Visual Studio Code",
    ).perform
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
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_quoted_heredoc_completion
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "str = <<-'STR'",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 1, character: 2 },
      "\n",
      "Visual Studio Code",
    ).perform
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
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_completing_end_token_inside_parameters
    document = RubyLsp::RubyDocument.new(
      source: +"foo(proc do\n)",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 1, character: 0 },
      "\n",
      "Visual Studio Code",
    ).perform
    expected_edits = [
      {
        range: { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } },
        newText: "\n",
      },
      {
        range: { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } },
        newText: "end",
      },
      {
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } },
        newText: "$0",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_completing_end_token_inside_brackets
    document = RubyLsp::RubyDocument.new(
      source: +"foo[proc do\n]",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 1, character: 0 },
      "\n",
      "Visual Studio Code",
    ).perform
    expected_edits = [
      {
        range: { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } },
        newText: "\n",
      },
      {
        range: { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } },
        newText: "end",
      },
      {
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } },
        newText: "$0",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_no_snippet_if_not_vs_code
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "class Foo",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 1, character: 2 },
      "\n",
      "Foo",
    ).perform
    expected_edits = [
      {
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } },
        newText: "\n",
      },
      {
        range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } },
        newText: "end",
      },
    ]
    assert_equal(expected_edits.to_json, T.must(edits).to_json)
  end

  def test_includes_snippets_on_vscode_insiders
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "class Foo",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 1, character: 2 },
      "\n",
      "Visual Studio Code - Insiders",
    ).perform
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

  def test_includes_snippets_on_cursor
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "class Foo",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 1, character: 2 },
      "\n",
      "Cursor",
    ).perform
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

  def test_does_not_confuse_class_parameter_with_keyword
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "link_to :something,\n  class: 'foo',\n  ",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 2, character: 4 },
      "\n",
      "Visual Studio Code",
    ).perform

    assert_empty(edits)
  end

  def test_allows_end_completion_when_parenthesis_are_present
    document = RubyLsp::RubyDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        text: "if(\n  ",
      }],
      version: 2,
    )
    document.parse!

    edits = RubyLsp::Requests::OnTypeFormatting.new(
      document,
      { line: 1, character: 2 },
      "\n",
      "Visual Studio Code",
    ).perform

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
end
