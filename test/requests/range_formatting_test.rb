# typed: true
# frozen_string_literal: true

require "test_helper"

class RangeFormattingTest < Minitest::Test
  def setup
    @global_state = RubyLsp::GlobalState.new
    @global_state.formatter = "syntax_tree"
    regular_formatter = RubyLsp::Requests::Support::SyntaxTreeFormatter.new
    @global_state.register_formatter("syntax_tree", regular_formatter)
    @global_state.stubs(:active_formatter).returns(regular_formatter)
    source = +<<~RUBY
      class Foo

        def foo
          [
          1,
          2,
          3,
          4,
          ]
        end
      end
    RUBY
    @document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI::Generic.from_path(path: __FILE__),
      global_state: @global_state,
    )
  end

  def test_syntax_tree_supports_range_formatting
    # Note how only the selected array is formatted, otherwise the blank lines would be removed
    expect_formatted_range({ start: { line: 3, character: 2 }, end: { line: 8, character: 5 } }, <<~RUBY)
      class Foo

        def foo
          [1, 2, 3, 4]
        end
      end
    RUBY
  end

  private

  def expect_formatted_range(range, expected)
    edits = T.must(RubyLsp::Requests::RangeFormatting.new(@global_state, @document, { range: range }).perform)

    @document.push_edits(
      edits.map do |edit|
        { range: edit.range.to_hash.transform_values(&:to_hash), text: edit.new_text }
      end,
      version: 2,
    )

    assert_equal(expected, @document.source)
  end
end
