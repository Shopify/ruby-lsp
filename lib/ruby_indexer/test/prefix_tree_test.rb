# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyIndexer
  class PrefixTreeTest < Minitest::Test
    def test_empty
      tree = PrefixTree.new([])

      assert_empty(tree.search(""))
      assert_empty(tree.search("foo"))
    end

    def test_single_item
      tree = PrefixTree.new(["foo"])

      assert_equal(["foo"], tree.search(""))
      assert_equal(["foo"], tree.search("foo"))
      assert_empty(tree.search("bar"))
    end

    def test_multiple_items
      tree = PrefixTree.new(["foo", "bar", "baz"])

      assert_equal(["foo", "bar", "baz"], tree.search(""))
      assert_equal(["bar", "baz"], tree.search("b"))
      assert_equal(["foo"], tree.search("fo"))
      assert_equal(["bar", "baz"], tree.search("ba"))
      assert_equal(["baz"], tree.search("baz"))
      assert_empty(tree.search("qux"))
    end

    def test_multiple_prefixes
      tree = PrefixTree.new(["fo", "foo"])

      assert_equal(["fo", "foo"], tree.search(""))
      assert_equal(["fo", "foo"], tree.search("f"))
      assert_equal(["fo", "foo"], tree.search("fo"))
      assert_equal(["foo"], tree.search("foo"))
      assert_empty(tree.search("fooo"))
    end

    def test_multiple_prefixes_with_shuffled_order
      tree = PrefixTree.new([
        "foo/bar/base",
        "foo/bar/on",
        "foo/bar/support/selection",
        "foo/bar/support/runner",
        "foo/internal",
        "foo/bar/document",
        "foo/bar/code",
        "foo/bar/support/rails",
        "foo/bar/diagnostics",
        "foo/bar/document2",
        "foo/bar/support/runner2",
        "foo/bar/support/diagnostic",
        "foo/document",
        "foo/bar/formatting",
        "foo/bar/support/highlight",
        "foo/bar/semantic",
        "foo/bar/support/prefix",
        "foo/bar/folding",
        "foo/bar/selection",
        "foo/bar/support/syntax",
        "foo/bar/document3",
        "foo/bar/hover",
        "foo/bar/support/semantic",
        "foo/bar/support/source",
        "foo/bar/inlay",
        "foo/requests",
        "foo/bar/support/formatting",
        "foo/bar/path",
        "foo/executor",
      ])

      assert_equal(
        [
          "foo/bar/support/selection",
          "foo/bar/support/semantic",
          "foo/bar/support/syntax",
          "foo/bar/support/source",
          "foo/bar/support/runner",
          "foo/bar/support/runner2",
          "foo/bar/support/rails",
          "foo/bar/support/diagnostic",
          "foo/bar/support/highlight",
          "foo/bar/support/prefix",
          "foo/bar/support/formatting",
        ],
        tree.search("foo/bar/support"),
      )
    end
  end
end
