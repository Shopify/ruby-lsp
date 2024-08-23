# typed: true
# frozen_string_literal: true

require "test_helper"

class RubyDocumentTest < Minitest::Test
  def test_valid_incremental_edits
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI("file:///foo.rb"))
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
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI("file:///foo.rb"))
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
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI("file:///foo.rb"))
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
    document = RubyLsp::RubyDocument.new(source: +"", version: 1, uri: URI("file:///foo.rb"))

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
    document = RubyLsp::RubyDocument.new(source: +"puts 'a'", version: 1, uri: URI("file:///foo.rb"))

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
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI("file:///foo.rb"))
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
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI("file:///foo.rb"))
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
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI("file:///foo.rb"))
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

  def test_document_handle_4_byte_unicode_characters
    source = +<<~RUBY
      class Foo
        a = "👋"
      end
    RUBY
    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///foo.rb"),
      encoding: Encoding::UTF_16LE,
    )

    document.push_edits(
      [
        { range: { start: { line: 1, character: 9 }, end: { line: 1, character: 9 } }, text: "s" },
      ],
      version: 2,
    )

    document.parse

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

    assert_equal(<<~RUBY, document.source)
      class Foo
        a = "👋s"
        puts 'a'
      end
    RUBY
  end

  def test_failing_to_parse_indicates_syntax_error
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI("file:///foo.rb"))
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
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI("file:///foo.rb"))
      def foo
    RUBY

    assert_predicate(document, :syntax_error?)
  end

  def test_locate
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: URI("file:///foo/bar.rb"))
      class Post < ActiveRecord::Base
        scope :published do
          # find posts that are published
          where(published: true)
        end
      end
    RUBY

    # Locate the `ActiveRecord` module
    node_context = document.locate_node({ line: 0, character: 19 })
    assert_instance_of(Prism::ConstantReadNode, node_context.node)
    assert_equal("ActiveRecord", T.cast(node_context.node, Prism::ConstantReadNode).location.slice)

    assert_instance_of(Prism::ConstantPathNode, node_context.parent)
    assert_equal(
      "ActiveRecord",
      T.must(T.cast(node_context.parent, Prism::ConstantPathNode).child_nodes.first).location.slice,
    )

    # Locate the `Base` class
    node_context = document.locate_node({ line: 0, character: 27 })
    found = T.cast(node_context.node, Prism::ConstantPathNode)
    assert_equal(:ActiveRecord, T.cast(found.parent, Prism::ConstantReadNode).name)
    assert_equal(:Base, found.name)

    # Locate the `where` invocation
    node_context = document.locate_node({ line: 3, character: 4 })
    assert_equal("where", T.cast(node_context.node, Prism::CallNode).message)
  end

  def test_locate_returns_nesting
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: URI("file:///foo/bar.rb"))
      module Foo
        class Other
          def do_it
            Hello
          end
        end

        class Bar
          def baz
            Qux
          end
        end
      end
    RUBY

    node_context = document.locate_node({ line: 9, character: 6 })
    assert_equal("Qux", T.cast(node_context.node, Prism::ConstantReadNode).location.slice)
    assert_equal(["Foo", "Bar"], node_context.nesting)

    node_context = document.locate_node({ line: 3, character: 6 })
    assert_equal("Hello", T.cast(node_context.node, Prism::ConstantReadNode).location.slice)
    assert_equal(["Foo", "Other"], node_context.nesting)
  end

  def test_locate_returns_call_node
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: URI("file:///foo/bar.rb"))
      module Foo
        class Other
          def do_it
            hello :foo
            :bar
          end
        end
      end
    RUBY

    node_context = document.locate_node({ line: 3, character: 14 })
    assert_equal(":foo", T.must(node_context.node).slice)
    assert_equal(:hello, T.must(node_context.call_node).name)

    node_context = document.locate_node({ line: 4, character: 8 })
    assert_equal(":bar", T.must(node_context.node).slice)
    assert_nil(node_context.call_node)
  end

  def test_locate_returns_call_node_nested
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: URI("file:///foo/bar.rb"))
      module Foo
        class Other
          def do_it
            goodbye(hello(:foo))
          end
        end
      end
    RUBY

    node_context = document.locate_node({ line: 3, character: 22 })
    assert_equal(":foo", T.must(node_context.node).slice)
    assert_equal(:hello, T.must(node_context.call_node).name)
  end

  def test_locate_returns_call_node_for_blocks
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: URI("file:///foo/bar.rb"))
      foo do
        "hello"
      end
    RUBY

    node_context = document.locate_node({ line: 1, character: 4 })
    assert_equal(:foo, T.must(node_context.call_node).name)
  end

  def test_locate_returns_call_node_ZZZ
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: URI("file:///foo/bar.rb"))
      foo(
        if bar(1, 2, 3)
          "hello" # this is the target
        end
      end
    RUBY

    node_context = document.locate_node({ line: 2, character: 6 })
    assert_equal(:foo, T.must(node_context.call_node).name)
  end

  def test_locate_returns_correct_nesting_when_specifying_target_classes
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: URI("file:///foo/bar.rb"))
      module Foo
        class Bar
          def baz
            Qux
          end
        end
      end
    RUBY

    node_context = document.locate_node({ line: 3, character: 6 }, node_types: [Prism::ConstantReadNode])
    found = node_context.node
    assert_equal("Qux", T.cast(found, Prism::ConstantReadNode).location.slice)
    assert_equal(["Foo", "Bar"], node_context.nesting)
  end

  def test_reparsing_without_new_edits_does_nothing
    text = "def foo; end"

    document = RubyLsp::RubyDocument.new(source: +"", version: 1, uri: URI("file:///foo/bar.rb"))
    document.push_edits(
      [{ range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } }, text: text }],
      version: 2,
    )

    parse_result = Prism.parse(text)

    # When there's a new edit, we parse it the first `parse` invocation
    Prism.expects(:parse).with(document.source).once.returns(parse_result)
    document.parse

    # If there are no new edits, we don't do anything
    Prism.expects(:parse).never
    document.parse

    document.push_edits(
      [{ range: { start: { line: 0, character: 12 }, end: { line: 0, character: 12 } }, text: "\ndef bar; end" }],
      version: 3,
    )

    # If there's another edit, we parse it once again
    Prism.expects(:parse).with(document.source).once.returns(parse_result)
    document.parse
  end

  def test_cache_set_and_get
    document = RubyLsp::RubyDocument.new(source: +"", version: 1, uri: URI("file:///foo/bar.rb"))
    value = [1, 2, 3]

    assert_equal(value, document.cache_set("textDocument/semanticHighlighting", value))
    assert_equal(value, document.cache_get("textDocument/semanticHighlighting"))
  end

  def test_no_sigil
    document = RubyLsp::RubyDocument.new(
      source: +"# frozen_string_literal: true",
      version: 1,
      uri: URI("file:///foo/bar.rb"),
    )
    assert_equal(RubyLsp::RubyDocument::SorbetLevel::None, document.sorbet_level)
  end

  def test_sigil_ignore
    document = RubyLsp::RubyDocument.new(source: +"# typed: ignore", version: 1, uri: URI("file:///foo/bar.rb"))
    assert_equal(RubyLsp::RubyDocument::SorbetLevel::Ignore, document.sorbet_level)
  end

  def test_sigil_false
    document = RubyLsp::RubyDocument.new(source: +"# typed: false", version: 1, uri: URI("file:///foo/bar.rb"))
    assert_equal(RubyLsp::RubyDocument::SorbetLevel::False, document.sorbet_level)
  end

  def test_sigil_true
    document = RubyLsp::RubyDocument.new(source: +"# typed: true", version: 1, uri: URI("file:///foo/bar.rb"))
    assert_equal(RubyLsp::RubyDocument::SorbetLevel::True, document.sorbet_level)
  end

  def test_sigil_strict
    document = RubyLsp::RubyDocument.new(source: +"# typed: strict", version: 1, uri: URI("file:///foo/bar.rb"))
    assert_equal(RubyLsp::RubyDocument::SorbetLevel::Strict, document.sorbet_level)
  end

  def test_sigil_strong
    document = RubyLsp::RubyDocument.new(source: +"# typed: strong", version: 1, uri: URI("file:///foo/bar.rb"))
    assert_equal(RubyLsp::RubyDocument::SorbetLevel::Strict, document.sorbet_level)
  end

  def test_sorbet_sigil_only_in_magic_comment
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI("file:///foo/bar.rb"))
      # typed: false

      def foo
        some_string = "# typed: true"
      end

      # Shouldn't be tricked by the following comment:
      # ```
      # # typed: strict
      #
      # def main; end
      # ```
      def bar; end

      def baz
        <<-CODE
          # typed: strong
        CODE
      end
    RUBY
    assert_equal(RubyLsp::RubyDocument::SorbetLevel::False, document.sorbet_level)
  end

  def test_locating_compact_namespace_declaration
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI("file:///foo/bar.rb"))
      class Foo::Bar
      end

      class Baz
      end
    RUBY

    node_context = document.locate_node({ line: 0, character: 11 })
    assert_empty(node_context.nesting)
    assert_equal("Foo::Bar", T.must(node_context.node).slice)

    node_context = document.locate_node({ line: 3, character: 6 })
    assert_empty(node_context.nesting)
    assert_equal("Baz", T.must(node_context.node).slice)
  end

  def test_locating_singleton_contexts
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI("file:///foo/bar.rb"))
      class Foo
        hello1

        def self.bar
          hello2
        end

        class << self
          hello3

          def baz
            hello4
          end
        end

        def qux
          hello5
        end
      end
    RUBY

    node_context = document.locate_node({ line: 1, character: 2 })
    assert_equal(["Foo"], node_context.nesting)
    assert_nil(node_context.surrounding_method)

    node_context = document.locate_node({ line: 4, character: 4 })
    assert_equal(["Foo", "<Class:Foo>"], node_context.nesting)
    assert_equal("bar", node_context.surrounding_method)

    node_context = document.locate_node({ line: 8, character: 4 })
    assert_equal(["Foo", "<Class:Foo>"], node_context.nesting)
    assert_nil(node_context.surrounding_method)

    node_context = document.locate_node({ line: 11, character: 6 })
    assert_equal(["Foo", "<Class:Foo>"], node_context.nesting)
    assert_equal("baz", node_context.surrounding_method)

    node_context = document.locate_node({ line: 16, character: 6 })
    assert_equal(["Foo"], node_context.nesting)
    assert_equal("qux", node_context.surrounding_method)
  end

  def test_locate_first_within_range
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI("file:///foo/bar.rb"))
      method_call(other_call).each do |a|
        nested_call(fourth_call).each do |b|
        end
      end
    RUBY

    target = document.locate_first_within_range(
      { start: { line: 0, character: 0 }, end: { line: 3, character: 3 } },
      node_types: [Prism::CallNode],
    )

    assert_equal("each", T.cast(target, Prism::CallNode).message)

    target = document.locate_first_within_range(
      { start: { line: 1, character: 2 }, end: { line: 2, character: 5 } },
      node_types: [Prism::CallNode],
    )

    assert_equal("each", T.cast(target, Prism::CallNode).message)
  end

  def test_uncached_requests_return_empty_cache_object
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI("file:///foo/bar.rb"))
      class Foo
      end
    RUBY

    assert_same(document.cache_get("textDocument/codeLens"), RubyLsp::Document::EMPTY_CACHE)
    document.cache_set("textDocument/codeLens", nil)
    assert_nil(document.cache_get("textDocument/codeLens"))
  end

  private

  def assert_error_edit(actual, error_range)
    assert_equal([error_range].to_json, actual.to_json)
  end
end
