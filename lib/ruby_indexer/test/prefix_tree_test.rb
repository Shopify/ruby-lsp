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

    def test_inserting_diverging_keys_splits_the_shared_edge
      tree = PrefixTree.new #: PrefixTree[String]
      tree.insert("foobar", "foobar")
      tree.insert("foobaz", "foobaz")

      assert_equal(["foobar", "foobaz"], tree.search("").sort)
      assert_equal(["foobar", "foobaz"], tree.search("f").sort)
      assert_equal(["foobar", "foobaz"], tree.search("fooba").sort)
      assert_equal(["foobar"], tree.search("foobar"))
      assert_equal(["foobaz"], tree.search("foobaz"))
    end

    def test_inserting_a_key_that_ends_in_the_middle_of_an_existing_edge
      tree = PrefixTree.new #: PrefixTree[String]
      tree.insert("foobar", "foobar")
      tree.insert("foo", "foo")

      assert_equal(["foo", "foobar"], tree.search("foo").sort)
      assert_equal(["foobar"], tree.search("foob"))
      assert_equal(["foobar"], tree.search("foobar"))
    end

    def test_searching_for_prefixes_that_end_in_the_middle_of_an_edge
      tree = PrefixTree.new #: PrefixTree[String]
      tree.insert("foobar", "foobar")

      assert_equal(["foobar"], tree.search("f"))
      assert_equal(["foobar"], tree.search("fooba"))
      assert_empty(tree.search("foox"))
      assert_empty(tree.search("foobarx"))
      assert_empty(tree.search("x"))
    end

    def test_keys_without_a_shared_prefix
      tree = PrefixTree.new #: PrefixTree[String]
      tree.insert("abc", "abc")
      tree.insert("xyz", "xyz")

      assert_equal(["abc", "xyz"], tree.search("").sort)
      assert_equal(["abc"], tree.search("a"))
      assert_equal(["xyz"], tree.search("x"))
    end

    def test_deleting_after_an_edge_was_split
      tree = PrefixTree.new #: PrefixTree[String]
      tree.insert("foobar", "foobar")
      tree.insert("foobaz", "foobaz")

      tree.delete("foobar")
      assert_empty(tree.search("foobar"))
      assert_equal(["foobaz"], tree.search("foo"))
      assert_equal(["foobaz"], tree.search("foobaz"))

      tree.insert("foobar", "again")
      assert_equal(["again"], tree.search("foobar"))
      assert_equal(["again", "foobaz"], tree.search("foo").sort)
    end

    def test_deleting_with_a_key_that_ends_in_the_middle_of_an_edge
      tree = PrefixTree.new #: PrefixTree[String]
      tree.insert("foobar", "foobar")

      tree.delete("foo")
      assert_empty(tree.search("foobar"))
      assert_empty(tree.search(""))
    end

    def test_deleting_keeps_the_ancestor_key_when_a_longer_key_is_removed
      tree = PrefixTree.new #: PrefixTree[String]
      tree.insert("foo", "foo")
      tree.insert("foobar", "foobar")
      tree.insert("foobaz", "foobaz")

      tree.delete("foobar")
      tree.delete("foobaz")
      assert_equal(["foo"], tree.search(""))
      assert_equal(["foo"], tree.search("foo"))
    end
  end
end
