# typed: true
# frozen_string_literal: true

require "test_helper"

class DocumentTest < Minitest::Test
  def test_valid_incremental_edits
    document = RubyLsp::Document.new(+<<~RUBY)
      def foo
      end
    RUBY

    # Write puts 'a' in incremental edits
    document.push_edits([{ range: { start: { line: 0, character: 7 }, end: { line: 0, character: 7 } }, text: "\n  " }])
    document.push_edits([{ range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } }, text: "p" }])
    document.push_edits([{ range: { start: { line: 1, character: 3 }, end: { line: 1, character: 3 } }, text: "u" }])
    document.push_edits([{ range: { start: { line: 1, character: 4 }, end: { line: 1, character: 4 } }, text: "t" }])
    document.push_edits([{ range: { start: { line: 1, character: 5 }, end: { line: 1, character: 5 } }, text: "s" }])
    document.push_edits([{ range: { start: { line: 1, character: 6 }, end: { line: 1, character: 6 } }, text: " " }])
    document.push_edits([{ range: { start: { line: 1, character: 7 }, end: { line: 1, character: 7 } }, text: "'" }])
    document.push_edits([{ range: { start: { line: 1, character: 8 }, end: { line: 1, character: 8 } }, text: "a" }])
    document.push_edits([{ range: { start: { line: 1, character: 9 }, end: { line: 1, character: 9 } }, text: "'" }])

    assert_equal(<<~RUBY, document.source)
      def foo
        puts 'a'
      end
    RUBY
  end

  def test_deletion_full_node
    document = RubyLsp::Document.new(+<<~RUBY)
      def foo
        puts 'a' # comment
      end
    RUBY

    # Delete puts 'a' in incremental edits
    document.push_edits([{ range: { start: { line: 1, character: 2 }, end: { line: 1, character: 11 } }, text: "" }])

    assert_equal(<<~RUBY, document.source)
      def foo
        # comment
      end
    RUBY
  end

  def test_deletion_single_character
    document = RubyLsp::Document.new(+<<~RUBY)
      def foo
        puts 'a'
      end
    RUBY

    # Delete puts 'a' in incremental edits
    document.push_edits([{ range: { start: { line: 1, character: 8 }, end: { line: 1, character: 9 } }, text: "" }])

    assert_equal(<<~RUBY, document.source)
      def foo
        puts ''
      end
    RUBY
  end

  def test_add_delete_single_character
    document = RubyLsp::Document.new(+"")

    # Add a
    document.push_edits([{ range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } }, text: "a" }])

    assert_equal("a", document.source)

    # Delete a
    document.push_edits([{ range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } }, text: "" }])

    assert_empty(document.source)
  end

  def test_replace
    document = RubyLsp::Document.new(+"puts 'a'")

    # Replace for puts 'b'
    document.push_edits([{ range: { start: { line: 0, character: 0 }, end: { line: 0, character: 8 } },
                           text: "puts 'b'", }])

    assert_equal("puts 'b'", document.source)
  end

  def test_new_line_and_char_addition
    document = RubyLsp::Document.new(+<<~RUBY)
      # frozen_string_literal: true

      class Foo
        def foo
        end
      end
    RUBY

    # Write puts 'a' in incremental edits
    document.push_edits([{ range: { start: { line: 3, character: 9 }, end: { line: 3, character: 9 } },
                           rangeLength: 0, text: "\n    ", }])
    document.push_edits([{ range: { start: { line: 4, character: 4 }, end: { line: 4, character: 4 } },
                           rangeLength: 0, text: "a", }])

    assert_equal(<<~RUBY, document.source)
      # frozen_string_literal: true

      class Foo
        def foo
          a
        end
      end
    RUBY
  end

  def test_multi_cursor_edit
    document = RubyLsp::Document.new(+<<~RUBY)
      # frozen_string_literal: true



    RUBY

    # Write puts 'hello' with two cursors on line 1 and 3
    document.push_edits([
      { range: { start: { line: 3, character: 0 }, end: { line: 3, character: 0 } }, text: "p" },
      { range: { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } }, text: "p" },
    ])
    document.push_edits([
      { range: { start: { line: 3, character: 1 }, end: { line: 3, character: 1 } }, text: "u" },
      { range: { start: { line: 1, character: 1 }, end: { line: 1, character: 1 } }, text: "u" },
    ])
    document.push_edits([
      { range: { start: { line: 3, character: 2 }, end: { line: 3, character: 2 } }, text: "t" },
      { range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } }, text: "t" },
    ])
    document.push_edits([
      { range: { start: { line: 3, character: 3 }, end: { line: 3, character: 3 } }, text: "s" },
      { range: { start: { line: 1, character: 3 }, end: { line: 1, character: 3 } }, text: "s" },
    ])
    document.push_edits([
      { range: { start: { line: 3, character: 4 }, end: { line: 3, character: 4 } }, text: " " },
      { range: { start: { line: 1, character: 4 }, end: { line: 1, character: 4 } }, text: " " },
    ])
    document.push_edits([
      { range: { start: { line: 3, character: 5 }, end: { line: 3, character: 5 } }, text: "'" },
      { range: { start: { line: 1, character: 5 }, end: { line: 1, character: 5 } }, text: "'" },
    ])
    document.push_edits([
      { range: { start: { line: 3, character: 6 }, end: { line: 3, character: 6 } }, text: "h" },
      { range: { start: { line: 1, character: 6 }, end: { line: 1, character: 6 } }, text: "h" },
    ])
    document.push_edits([
      { range: { start: { line: 3, character: 7 }, end: { line: 3, character: 7 } }, text: "e" },
      { range: { start: { line: 1, character: 7 }, end: { line: 1, character: 7 } }, text: "e" },
    ])
    document.push_edits([
      { range: { start: { line: 3, character: 8 }, end: { line: 3, character: 8 } }, text: "l" },
      { range: { start: { line: 1, character: 8 }, end: { line: 1, character: 8 } }, text: "l" },
    ])
    document.push_edits([
      { range: { start: { line: 3, character: 9 }, end: { line: 3, character: 9 } }, text: "l" },
      { range: { start: { line: 1, character: 9 }, end: { line: 1, character: 9 } }, text: "l" },
    ])
    document.push_edits([
      { range: { start: { line: 3, character: 10 }, end: { line: 3, character: 10 } }, text: "o" },
      { range: { start: { line: 1, character: 10 }, end: { line: 1, character: 10 } }, text: "o" },
    ])
    document.push_edits([
      { range: { start: { line: 3, character: 11 }, end: { line: 3, character: 11 } }, text: "'" },
      { range: { start: { line: 1, character: 11 }, end: { line: 1, character: 11 } }, text: "'" },
    ])

    assert_equal(<<~RUBY, document.source)
      # frozen_string_literal: true
      puts 'hello'

      puts 'hello'
    RUBY
  end

  def test_syntax_error_on_addition_returns_diagnostics
    document = RubyLsp::Document.new(+<<~RUBY)
      # frozen_string_literal: true

      a
    RUBY

    error_edit = { range: { start: { line: 2, character: 2 }, end: { line: 2, character: 2 } }, text: "=" }

    document.push_edits([
      { range: { start: { line: 2, character: 1 }, end: { line: 2, character: 1 } }, text: " " },
    ])
    document.parse
    document.push_edits([error_edit])
    document.parse
    assert_error_edit(document.syntax_error_edits, error_edit)
    assert_predicate(document, :syntax_errors?)

    assert_equal(<<~RUBY, document.source)
      # frozen_string_literal: true

      a =
    RUBY
  end

  def test_syntax_error_on_removal_returns_diagnostics
    document = RubyLsp::Document.new(+<<~RUBY)
      # frozen_string_literal: true

      class Foo
      end
    RUBY

    error_edit = { range: { start: { line: 3, character: 2 }, end: { line: 3, character: 3 } }, text: "" }
    document.push_edits([error_edit])
    document.parse
    assert_error_edit(document.syntax_error_edits, error_edit)
    assert_predicate(document, :syntax_errors?)

    assert_equal(<<~RUBY, document.source)
      # frozen_string_literal: true

      class Foo
      en
    RUBY
  end

  def test_pushing_edits_to_document_with_unicode
    document = RubyLsp::Document.new(+<<~RUBY)
      chars = ["億"]
    RUBY

    # Write puts 'a' in incremental edits
    document.push_edits([{ range: { start: { line: 0, character: 13 }, end: { line: 0, character: 13 } }, text: "\n" }])
    document.push_edits([{ range: { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } }, text: "p" }])
    document.push_edits([{ range: { start: { line: 1, character: 1 }, end: { line: 1, character: 1 } }, text: "u" }])
    document.push_edits([{ range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } }, text: "t" }])
    document.push_edits([{ range: { start: { line: 1, character: 3 }, end: { line: 1, character: 3 } }, text: "s" }])
    document.push_edits([{ range: { start: { line: 1, character: 4 }, end: { line: 1, character: 4 } }, text: " " }])
    document.push_edits([{ range: { start: { line: 1, character: 5 }, end: { line: 1, character: 5 } }, text: "'" }])
    document.push_edits([{ range: { start: { line: 1, character: 6 }, end: { line: 1, character: 6 } }, text: "a" }])
    document.push_edits([{ range: { start: { line: 1, character: 7 }, end: { line: 1, character: 7 } }, text: "'" }])

    assert_equal(<<~RUBY, document.source)
      chars = ["億"]
      puts 'a'
    RUBY
  end

  def test_parsed_returns_true_when_parsed_successfully
    document = RubyLsp::Document.new(+<<~RUBY)
      # frozen_string_literal: true
      puts 'hello'
    RUBY

    assert_predicate(document, :parsed?)
  end

  def test_parsed_returns_false_when_parsing_fails
    document = RubyLsp::Document.new(+<<~RUBY)
      class Foo
    RUBY

    refute_predicate(document, :parsed?)
  end

  private

  def assert_error_edit(actual, error_range)
    assert_equal([error_range].to_json, actual.to_json)
  end
end
