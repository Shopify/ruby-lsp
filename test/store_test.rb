# frozen_string_literal: true

require "test_helper"

class StoreTest < Minitest::Test
  def setup
    @store = RubyLsp::Store.new
    @store.set("/foo/bar.rb", "def foo; end")
  end

  def test_hash_accessors
    assert_equal(RubyLsp::Store::ParsedTree.new("def foo; end"), @store["/foo/bar.rb"])
  end

  def test_reads_from_file_if_missing_in_store
    file = Tempfile.new("foo.rb")
    file.write("def great_code; end")
    file.rewind

    assert_equal(RubyLsp::Store::ParsedTree.new("def great_code; end"), @store[file.path])
  ensure
    file.close
    file.unlink
  end

  def test_store_ignores_syntax_errors
    @store.set("/foo/bar.rb", "def bar; end; end")

    assert_equal(RubyLsp::Store::ParsedTree.new("def foo; end"), @store["/foo/bar.rb"])
  end

  def test_clear
    @store.clear

    assert_empty(@store.instance_variable_get(:@state))
  end

  def test_delete
    @store.delete("/foo/bar.rb")

    assert_empty(@store.instance_variable_get(:@state))
  end

  def test_cache
    # Cache warms up the first time and then re-uses the previous result
    counter = 0

    5.times do
      @store["/foo/bar.rb"].cache_fetch(RubyLsp::Requests::FoldingRanges) do
        counter += 1
      end
    end

    assert_equal(1, counter)

    # After the entry in the storage is updated, the cache is invalidated
    @store.set("/foo/bar.rb", "def bar; end")
    5.times do
      @store["/foo/bar.rb"].cache_fetch(RubyLsp::Requests::FoldingRanges) do
        counter += 1
      end
    end

    assert_equal(2, counter)
  end
end
