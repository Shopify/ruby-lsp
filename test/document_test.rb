# typed: true
# frozen_string_literal: true

require "test_helper"

class DocumentTest < Minitest::Test
  def test_valid_incremental_edits
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: "file:///foo.rb")
      def foo
      end
    RUBY

    # Write puts 'a' in incremental edits
    document.push_edits(
      [{ range: { start: { line: 0, character: 7 }, end: { line: 0, character: 7 } }, text: "\n  " }],
      version: 2,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } }, text: "p" }],
      version: 3,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 3 }, end: { line: 1, character: 3 } }, text: "u" }],
      version: 4,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 4 }, end: { line: 1, character: 4 } }, text: "t" }],
      version: 5,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 5 }, end: { line: 1, character: 5 } }, text: "s" }],
      version: 6,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 6 }, end: { line: 1, character: 6 } }, text: " " }],
      version: 7,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 7 }, end: { line: 1, character: 7 } }, text: "'" }],
      version: 8,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 8 }, end: { line: 1, character: 8 } }, text: "a" }],
      version: 9,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 9 }, end: { line: 1, character: 9 } }, text: "'" }], version: 10
    )

    assert_equal(<<~RUBY, document.source)
      def foo
        puts 'a'
      end
    RUBY
  end

  def test_deletion_full_node
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: "file:///foo.rb")
      def foo
        puts 'a' # comment
      end
    RUBY

    # Delete puts 'a' in incremental edits
    document.push_edits(
      [{ range: { start: { line: 1, character: 2 }, end: { line: 1, character: 11 } }, text: "" }],
      version: 2,
    )

    assert_equal(<<~RUBY, document.source)
      def foo
        # comment
      end
    RUBY
  end

  def test_deletion_single_character
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: "file:///foo.rb")
      def foo
        puts 'a'
      end
    RUBY

    # Delete puts 'a' in incremental edits
    document.push_edits(
      [{ range: { start: { line: 1, character: 8 }, end: { line: 1, character: 9 } }, text: "" }],
      version: 2,
    )

    assert_equal(<<~RUBY, document.source)
      def foo
        puts ''
      end
    RUBY
  end

  def test_add_delete_single_character
    document = RubyLsp::Document.new(source: +"", version: 1, uri: "file:///foo.rb")

    # Add a
    document.push_edits(
      [{ range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } }, text: "a" }],
      version: 2,
    )

    assert_equal("a", document.source)

    # Delete a
    document.push_edits(
      [{ range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } }, text: "" }],
      version: 3,
    )

    assert_empty(document.source)
  end

  def test_replace
    document = RubyLsp::Document.new(source: +"puts 'a'", version: 1, uri: "file:///foo.rb")

    # Replace for puts 'b'
    document.push_edits(
      [{
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 8 } },
        text: "puts 'b'",
      }],
      version: 2,
    )

    assert_equal("puts 'b'", document.source)
  end

  def test_new_line_and_char_addition
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: "file:///foo.rb")
      # frozen_string_literal: true

      class Foo
        def foo
        end
      end
    RUBY

    # Write puts 'a' in incremental edits
    document.push_edits(
      [{
        range: { start: { line: 3, character: 9 }, end: { line: 3, character: 9 } },
        rangeLength: 0,
        text: "\n    ",
      }],
      version: 2,
    )
    document.push_edits(
      [{
        range: { start: { line: 4, character: 4 }, end: { line: 4, character: 4 } },
        rangeLength: 0,
        text: "a",
      }],
      version: 3,
    )

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
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: "file:///foo.rb")
      # frozen_string_literal: true



    RUBY

    # Write puts 'hello' with two cursors on line 1 and 3
    document.push_edits(
      [
        { range: { start: { line: 3, character: 0 }, end: { line: 3, character: 0 } }, text: "p" },
        { range: { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } }, text: "p" },
      ],
      version: 2,
    )
    document.push_edits(
      [
        { range: { start: { line: 3, character: 1 }, end: { line: 3, character: 1 } }, text: "u" },
        { range: { start: { line: 1, character: 1 }, end: { line: 1, character: 1 } }, text: "u" },
      ],
      version: 3,
    )
    document.push_edits(
      [
        { range: { start: { line: 3, character: 2 }, end: { line: 3, character: 2 } }, text: "t" },
        { range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } }, text: "t" },
      ],
      version: 4,
    )
    document.push_edits(
      [
        { range: { start: { line: 3, character: 3 }, end: { line: 3, character: 3 } }, text: "s" },
        { range: { start: { line: 1, character: 3 }, end: { line: 1, character: 3 } }, text: "s" },
      ],
      version: 5,
    )
    document.push_edits(
      [
        { range: { start: { line: 3, character: 4 }, end: { line: 3, character: 4 } }, text: " " },
        { range: { start: { line: 1, character: 4 }, end: { line: 1, character: 4 } }, text: " " },
      ],
      version: 6,
    )
    document.push_edits(
      [
        { range: { start: { line: 3, character: 5 }, end: { line: 3, character: 5 } }, text: "'" },
        { range: { start: { line: 1, character: 5 }, end: { line: 1, character: 5 } }, text: "'" },
      ],
      version: 7,
    )
    document.push_edits(
      [
        { range: { start: { line: 3, character: 6 }, end: { line: 3, character: 6 } }, text: "h" },
        { range: { start: { line: 1, character: 6 }, end: { line: 1, character: 6 } }, text: "h" },
      ],
      version: 8,
    )
    document.push_edits(
      [
        { range: { start: { line: 3, character: 7 }, end: { line: 3, character: 7 } }, text: "e" },
        { range: { start: { line: 1, character: 7 }, end: { line: 1, character: 7 } }, text: "e" },
      ],
      version: 9,
    )
    document.push_edits(
      [
        { range: { start: { line: 3, character: 8 }, end: { line: 3, character: 8 } }, text: "l" },
        { range: { start: { line: 1, character: 8 }, end: { line: 1, character: 8 } }, text: "l" },
      ],
      version: 10,
    )
    document.push_edits(
      [
        { range: { start: { line: 3, character: 9 }, end: { line: 3, character: 9 } }, text: "l" },
        { range: { start: { line: 1, character: 9 }, end: { line: 1, character: 9 } }, text: "l" },
      ],
      version: 11,
    )
    document.push_edits(
      [
        { range: { start: { line: 3, character: 10 }, end: { line: 3, character: 10 } }, text: "o" },
        { range: { start: { line: 1, character: 10 }, end: { line: 1, character: 10 } }, text: "o" },
      ],
      version: 12,
    )
    document.push_edits(
      [
        { range: { start: { line: 3, character: 11 }, end: { line: 3, character: 11 } }, text: "'" },
        { range: { start: { line: 1, character: 11 }, end: { line: 1, character: 11 } }, text: "'" },
      ],
      version: 13,
    )

    assert_equal(<<~RUBY, document.source)
      # frozen_string_literal: true
      puts 'hello'

      puts 'hello'
    RUBY
  end

  def test_pushing_edits_to_document_with_unicode
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: "file:///foo.rb")
      chars = ["億"]
    RUBY

    # Write puts 'a' in incremental edits
    document.push_edits(
      [{ range: { start: { line: 0, character: 13 }, end: { line: 0, character: 13 } }, text: "\n" }],
      version: 2,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 0 }, end: { line: 1, character: 0 } }, text: "p" }],
      version: 3,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 1 }, end: { line: 1, character: 1 } }, text: "u" }],
      version: 4,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 2 }, end: { line: 1, character: 2 } }, text: "t" }],
      version: 5,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 3 }, end: { line: 1, character: 3 } }, text: "s" }],
      version: 6,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 4 }, end: { line: 1, character: 4 } }, text: " " }],
      version: 7,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 5 }, end: { line: 1, character: 5 } }, text: "'" }],
      version: 8,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 6 }, end: { line: 1, character: 6 } }, text: "a" }],
      version: 9,
    )
    document.push_edits(
      [{ range: { start: { line: 1, character: 7 }, end: { line: 1, character: 7 } }, text: "'" }],
      version: 10,
    )

    assert_equal(<<~RUBY, document.source)
      chars = ["億"]
      puts 'a'
    RUBY
  end

  def test_parsed_returns_true_when_parsed_successfully
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: "file:///foo.rb")
      # frozen_string_literal: true
      puts 'hello'
    RUBY

    assert_predicate(document, :parsed?)
  end

  def test_parsed_returns_false_when_parsing_fails
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: "file:///foo.rb")
      class Foo
    RUBY

    refute_predicate(document, :parsed?)
  end

  def test_document_handle_4_byte_unicode_characters
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: "file:///foo.rb", encoding: "utf-16")
      class Foo
        a = "👋"
      end
    RUBY

    document.push_edits(
      [
        { range: { start: { line: 1, character: 9 }, end: { line: 1, character: 9 } }, text: "s" },
      ],
      version: 2,
    )

    document.parse
    assert_predicate(document, :parsed?)

    assert_equal(<<~RUBY, document.source)
      class Foo
        a = "👋s"
      end
    RUBY

    document.push_edits(
      [{ range: { start: { line: 1, character: 11 }, end: { line: 1, character: 11 } }, text: "\n" }],
      version: 3,
    )
    document.push_edits(
      [{ range: { start: { line: 2, character: 0 }, end: { line: 2, character: 0 } }, text: "  p" }],
      version: 4,
    )
    document.push_edits(
      [{ range: { start: { line: 2, character: 3 }, end: { line: 2, character: 3 } }, text: "u" }],
      version: 5,
    )
    document.push_edits(
      [{ range: { start: { line: 2, character: 4 }, end: { line: 2, character: 4 } }, text: "t" }],
      version: 6,
    )
    document.push_edits(
      [{ range: { start: { line: 2, character: 5 }, end: { line: 2, character: 5 } }, text: "s" }],
      version: 7,
    )
    document.push_edits(
      [{ range: { start: { line: 2, character: 6 }, end: { line: 2, character: 6 } }, text: " " }],
      version: 8,
    )
    document.push_edits(
      [{ range: { start: { line: 2, character: 7 }, end: { line: 2, character: 7 } }, text: "'" }],
      version: 9,
    )
    document.push_edits(
      [{ range: { start: { line: 2, character: 8 }, end: { line: 2, character: 8 } }, text: "a" }],
      version: 10,
    )
    document.push_edits(
      [{ range: { start: { line: 2, character: 9 }, end: { line: 2, character: 9 } }, text: "'" }],
      version: 11,
    )

    document.parse
    assert_predicate(document, :parsed?)

    assert_equal(<<~RUBY, document.source)
      class Foo
        a = "👋s"
        puts 'a'
      end
    RUBY
  end

  def test_failing_to_parse_indicates_syntax_error
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: "file:///foo.rb")
      def foo
      end
    RUBY

    refute_predicate(document, :syntax_error?)

    document.push_edits(
      [{
        range: { start: { line: 0, character: 7 }, end: { line: 0, character: 7 } },
        text: "\n  def",
      }],
      version: 2,
    )
    document.parse

    assert_predicate(document, :syntax_error?)
  end

  def test_files_opened_with_syntax_errors_are_properly_marked
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: "file:///foo.rb")
      def foo
    RUBY

    assert_predicate(document, :syntax_error?)
  end

  def test_locate
    document = RubyLsp::Document.new(source: <<~RUBY, version: 1, uri: "file:///foo/bar.rb")
      class Post < ActiveRecord::Base
        scope :published do
          # find posts that are published
          where(published: true)
        end
      end
    RUBY

    # Locate the `ActiveRecord` module
    found, parent = document.locate_node({ line: 0, character: 19 })
    assert_instance_of(SyntaxTree::Const, found)
    assert_equal("ActiveRecord", T.cast(found, SyntaxTree::Const).value)

    assert_instance_of(SyntaxTree::VarRef, parent)
    assert_equal("ActiveRecord", T.cast(parent, SyntaxTree::VarRef).value.value)

    # Locate the `Base` class
    found, parent = T.cast(
      document.locate_node({ line: 0, character: 27 }),
      [SyntaxTree::Const, SyntaxTree::ConstPathRef],
    )
    assert_instance_of(SyntaxTree::Const, found)
    assert_equal("Base", found.value)

    assert_instance_of(SyntaxTree::ConstPathRef, parent)
    assert_equal("Base", parent.constant.value)
    assert_equal("ActiveRecord", T.cast(parent.parent, SyntaxTree::VarRef).value.value)

    # Locate the `where` invocation
    found, parent = T.cast(document.locate_node({ line: 3, character: 4 }), [SyntaxTree::Ident, SyntaxTree::CallNode])
    assert_instance_of(SyntaxTree::Ident, found)
    assert_equal("where", found.value)

    assert_instance_of(SyntaxTree::CallNode, parent)
  end

  def test_reparsing_without_new_edits_does_nothing
    document = RubyLsp::Document.new(source: +"", version: 1, uri: "file:///foo/bar.rb")
    document.push_edits(
      [{ range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } }, text: "def foo" }],
      version: 2,
    )

    document.parse
    assert_predicate(document, :syntax_error?)
    assert_empty(document.instance_variable_get(:@unparsed_edits))
  end

  private

  def assert_error_edit(actual, error_range)
    assert_equal([error_range].to_json, actual.to_json)
  end
end
