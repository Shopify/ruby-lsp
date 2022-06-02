# typed: true
# frozen_string_literal: true

require "test_helper"

class DocumentHighlightTest < Minitest::Test
  def test_non_highlightable_keyword
    code = <<~RUBY
      class Foo
      end
    RUBY

    assert_highlight(
      code,
      { line: 1, character: 2 },
      []
    )
  end

  def test_global_variables
    code = <<~RUBY
      $foo = 1

      def foo
        $foo
      end

      :$foo # ignore
    RUBY

    assert_highlight(
      code,
      { line: 0, character: 2 },
      [{ line: 0, start: 0, end: 4, kind: 3 }, { line: 3, start: 2, end: 6, kind: 2 }]
    )
  end

  def test_local_variables
    code = <<~RUBY
      foo = 1
      puts(foo = 2)

      foo

      def bar
        foo # ignore
      end

      :foo # ignore
    RUBY

    assert_highlight(
      code,
      { line: 0, character: 2 },
      [
        { line: 0, start: 0, end: 3, kind: 3 }, { line: 1, start: 5, end: 8, kind: 3 },
        { line: 3, start: 0, end: 3, kind: 2 },
      ]
    )
  end

  def test_constants
    code = <<~RUBY
      FOO = 1

      FOO

      def foo
        FOO
      end

      :FOO # ignore
    RUBY

    assert_highlight(
      code,
      { line: 0, character: 2 },
      [
        { line: 0, start: 0, end: 3, kind: 3 }, { line: 2, start: 0, end: 3, kind: 2 },
        { line: 5, start: 2, end: 5, kind: 2 },
      ]
    )
  end

  def test_class_variables
    code = <<~RUBY
      class Foo
        @@bar = 1

        def self.bar
          @@bar
        end
      end

      :@@bar # ignore
    RUBY

    assert_highlight(
      code,
      { line: 1, character: 2 },
      [
        { line: 1, start: 2, end: 7, kind: 3 }, { line: 4, start: 4, end: 9, kind: 2 },
      ]
    )
  end

  def test_instance_variables
    code = <<~RUBY
      class Foo
        def initialize
          @foo = 10
        end

        def foo
          @foo
        end

        :@foo # ignore
      end
    RUBY

    assert_highlight(
      code,
      { line: 2, character: 5 },
      [{ line: 2, start: 4, end: 8, kind: 3 }, { line: 6, start: 4, end: 8, kind: 2 }]
    )
  end

  private

  def assert_highlight(source, position, expected)
    document = RubyLsp::Document.new(source)
    actual = RubyLsp::Requests::DocumentHighlight.run(document, position)
    ranges = JSON.parse(actual.to_json, symbolize_names: true)

    assert_equal(expected.count, ranges.count)

    ranges = ranges.map do |hash|
      range = hash[:range]
      {
        line: range[:start][:line],
        start: range[:start][:character],
        end: range[:end][:character],
        kind: hash[:kind],
      }
    end

    assert_equal(expected, ranges)
  end
end
