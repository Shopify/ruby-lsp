# typed: true
# frozen_string_literal: true

require "test_helper"

class StoreTest < Minitest::Test
  def setup
    @store = RubyLsp::Store.new
    @store.set("/foo/bar.rb", "def foo; end")
  end

  def test_get
    assert_equal(RubyLsp::Document.new("def foo; end"), @store.get("/foo/bar.rb"))
  end

  def test_reads_from_file_if_missing_in_store
    file = Tempfile.new("foo.rb")
    file.write("def great_code; end")
    file.rewind

    assert_equal(RubyLsp::Document.new("def great_code; end"), @store.get(file.path))
  ensure
    T.must(file).close
    T.must(file).unlink
  end

  def test_store_ignores_syntax_errors
    @store.set("/foo/bar.rb", "def bar; end; end")

    assert_equal(RubyLsp::Document.new("def foo; end"), @store.get("/foo/bar.rb"))
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
      @store.cache_fetch("/foo/bar.rb", :folding_ranges) do
        counter += 1
      end
    end

    assert_equal(1, counter)

    # After the entry in the storage is updated, the cache is invalidated
    @store.set("/foo/bar.rb", "def bar; end")
    5.times do
      @store.cache_fetch("/foo/bar.rb", :folding_ranges) do
        counter += 1
      end
    end

    assert_equal(2, counter)
  end

  def test_push_edits
    uri = "/foo/bar.rb"
    @store.set(uri, +"def bar; end")

    # Write puts 'a' in incremental edits
    @store.push_edits(uri,
      [{ range: { start: { line: 0, character: 8 }, end: { line: 0, character: 8 } }, text: " " }])
    @store.push_edits(uri,
      [{ range: { start: { line: 0, character: 9 }, end: { line: 0, character: 9 } }, text: "p" }])
    @store.push_edits(uri,
      [{ range: { start: { line: 0, character: 10 }, end: { line: 0, character: 10 } }, text: "u" }])
    @store.push_edits(uri,
      [{ range: { start: { line: 0, character: 11 }, end: { line: 0, character: 11 } }, text: "t" }])
    @store.push_edits(uri,
      [{ range: { start: { line: 0, character: 12 }, end: { line: 0, character: 12 } }, text: "s" }])
    @store.push_edits(uri,
      [{ range: { start: { line: 0, character: 13 }, end: { line: 0, character: 13 } }, text: " " }])
    @store.push_edits(uri,
      [{ range: { start: { line: 0, character: 14 }, end: { line: 0, character: 14 } }, text: "'" }])
    @store.push_edits(uri,
      [{ range: { start: { line: 0, character: 15 }, end: { line: 0, character: 15 } }, text: "a" }])
    @store.push_edits(uri,
      [{ range: { start: { line: 0, character: 16 }, end: { line: 0, character: 16 } }, text: "'" }])
    @store.push_edits(uri,
      [{ range: { start: { line: 0, character: 17 }, end: { line: 0, character: 17 } }, text: ";" }])

    assert_equal(RubyLsp::Document.new("def bar; puts 'a'; end"), @store.get(uri))
  end
end
