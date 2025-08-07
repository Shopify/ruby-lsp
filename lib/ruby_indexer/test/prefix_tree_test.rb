# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyIndexer
  class PrefixTreeTest < Minitest::Test
    def test_empty
      tree = PrefixTree.new

      assert_empty(tree.search(""))
      assert_empty(tree.search("foo"))
    end

    def test_single_item
      tree = PrefixTree.new
      tree.insert("foo", "foo")

      assert_equal(["foo"], tree.search(""))
      assert_equal(["foo"], tree.search("foo"))
      assert_empty(tree.search("bar"))
    end

    def test_multiple_items
      tree = PrefixTree.new #: PrefixTree[String]
      ["foo", "bar", "baz"].each { |item| tree.insert(item, item) }

      assert_equal(["baz", "bar", "foo"], tree.search(""))
      assert_equal(["baz", "bar"], tree.search("b"))
      assert_equal(["foo"], tree.search("fo"))
      assert_equal(["baz", "bar"], tree.search("ba"))
      assert_equal(["baz"], tree.search("baz"))
      assert_empty(tree.search("qux"))
    end

    def test_multiple_prefixes
      tree = PrefixTree.new #: PrefixTree[String]
      ["fo", "foo"].each { |item| tree.insert(item, item) }

      assert_equal(["fo", "foo"], tree.search(""))
      assert_equal(["fo", "foo"], tree.search("f"))
      assert_equal(["fo", "foo"], tree.search("fo"))
      assert_equal(["foo"], tree.search("foo"))
      assert_empty(tree.search("fooo"))
    end

    def test_multiple_prefixes_with_shuffled_order
      tree = PrefixTree.new #: PrefixTree[String]
      [
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
      ].each { |item| tree.insert(item, item) }

      assert_equal(
        [
          "foo/bar/support/formatting",
          "foo/bar/support/prefix",
          "foo/bar/support/highlight",
          "foo/bar/support/diagnostic",
          "foo/bar/support/rails",
          "foo/bar/support/runner",
          "foo/bar/support/runner2",
          "foo/bar/support/source",
          "foo/bar/support/syntax",
          "foo/bar/support/semantic",
          "foo/bar/support/selection",
        ],
        tree.search("foo/bar/support"),
      )
    end

    def test_deletion
      tree = PrefixTree.new #: PrefixTree[String]
      ["foo/bar", "foo/baz"].each { |item| tree.insert(item, item) }
      assert_equal(["foo/baz", "foo/bar"], tree.search("foo"))

      tree.delete("foo/bar")
      assert_empty(tree.search("foo/bar"))
      assert_equal(["foo/baz"], tree.search("foo"))
    end

    def test_delete_does_not_impact_other_keys_with_the_same_value
      tree = PrefixTree.new #: PrefixTree[String]
      tree.insert("key1", "value")
      tree.insert("key2", "value")
      assert_equal(["value", "value"], tree.search("key"))

      tree.delete("key2")
      assert_empty(tree.search("key2"))
      assert_equal(["value"], tree.search("key1"))
    end

    def test_deleted_node_is_removed_from_the_tree
      tree = PrefixTree.new #: PrefixTree[String]
      tree.insert("foo/bar", "foo/bar")
      assert_equal(["foo/bar"], tree.search("foo"))

      tree.delete("foo/bar")
      root = tree.instance_variable_get(:@root)
      assert_empty(root.children)
    end

    def test_deleting_non_terminal_nodes
      tree = PrefixTree.new #: PrefixTree[String]
      tree.insert("abc", "value1")
      tree.insert("abcdef", "value2")

      tree.delete("abcdef")
      assert_empty(tree.search("abcdef"))
      assert_equal(["value1"], tree.search("abc"))
    end

    def test_overriding_values
      tree = PrefixTree.new #: PrefixTree[Integer]

      tree.insert("foo/bar", 123)
      assert_equal([123], tree.search("foo/bar"))

      tree.insert("foo/bar", 456)
      assert_equal([456], tree.search("foo/bar"))
    end
  end
end
