# frozen_string_literal: true

require "test_helper"

class StoreTest < Minitest::Test
  def test_hash_accessors
    store = Ruby::Lsp::Store.new
    store["/foo/bar.rb"] = "def foo; end"

    assert_equal(Ruby::Lsp::Store::ParsedTree.new("def foo; end"), store["/foo/bar.rb"])
  end

  def test_reads_from_file_if_missing_in_store
    store = Ruby::Lsp::Store.new

    file = Tempfile.new("foo.rb")
    file.write("def great_code; end")
    file.rewind

    assert_equal(Ruby::Lsp::Store::ParsedTree.new("def great_code; end"), store[file.path])
  ensure
    file.close
    file.unlink
  end

  def test_store_ignores_syntax_errors
    store = Ruby::Lsp::Store.new
    store["/foo/bar.rb"] = "def foo; end"
    store["/foo/bar.rb"] = "def bar; end; end"

    assert_equal(Ruby::Lsp::Store::ParsedTree.new("def foo; end"), store["/foo/bar.rb"])
  end

  def test_clear
    store = Ruby::Lsp::Store.new
    store["/foo/bar.rb"] = "def foo; end"
    store.clear

    assert_empty(store.instance_variable_get(:@state))
  end

  def test_delete
    store = Ruby::Lsp::Store.new
    store["/foo/bar.rb"] = "def foo; end"
    store.delete("/foo/bar.rb")

    assert_empty(store.instance_variable_get(:@state))
  end
end
