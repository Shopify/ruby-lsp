# typed: true
# frozen_string_literal: true

require "test_helper"

class StoreTest < Minitest::Test
  def setup
    @store = RubyLsp::Store.new
    @store.set(uri: URI("/foo/bar.rb"), source: "def foo; end", version: 1)
  end

  def test_get
    uri = URI("file:///foo/bar.rb")
    assert_equal(
      RubyLsp::Document.new(source: "def foo; end", version: 1, uri: uri),
      @store.get(uri),
    )
  end

  def test_handling_uris_with_spaces
    uri = URI("file:///foo%20bar/baz.rb")
    @store.set(uri: uri, source: "def foo; end", version: 1)

    assert_equal(
      RubyLsp::Document.new(source: "def foo; end", version: 1, uri: uri),
      @store.get(uri),
    )
  end

  def test_reading_from_tempfile_can_handle_spaces
    file = Tempfile.new("foo bar.rb")
    file.write("def great_code; end")
    file.rewind
    uri = URI("file://#{file.path}")

    assert_equal(
      RubyLsp::Document.new(source: "def great_code; end", version: 1, uri: uri),
      @store.get(uri),
    )
  ensure
    file&.close
    file&.unlink
  end

  def test_reads_from_file_if_missing_in_store
    file = Tempfile.new("foo.rb")
    file.write("def great_code; end")
    file.rewind
    uri = URI("file://#{file.path}")

    assert_equal(
      RubyLsp::Document.new(source: "def great_code; end", version: 1, uri: uri),
      @store.get(uri),
    )
  ensure
    file&.close
    file&.unlink
  end

  def test_push_edits_recovers_from_initial_syntax_error
    file = Tempfile.new("foo.rb")
    file.write("def great_code")
    file.rewind
    uri = URI("file://#{file.path}")
    document = @store.get(uri)

    refute_nil(document)
    assert_nil(document.tree)

    @store.push_edits(
      uri: uri,
      edits: [{ range: { start: { line: 0, character: 14 }, end: { line: 0, character: 14 } }, text: " ; end" }],
      version: 2,
    )

    document = @store.get(uri)
    document.parse
    refute_nil(document)
    refute_nil(document.tree)
  ensure
    file&.close
    file&.unlink
  end

  def test_clear
    @store.clear

    assert_empty(@store.instance_variable_get(:@state))
  end

  def test_empty?
    refute_empty(@store)

    @store.clear
    assert_empty(@store)
  end

  def test_delete
    @store.delete(URI("file:///foo/bar.rb"))

    assert_empty(@store.instance_variable_get(:@state))
  end

  def test_cache
    # Cache warms up the first time and then re-uses the previous result
    counter = 0
    uri = URI("file:///foo/bar.rb")

    5.times do
      @store.cache_fetch(uri, "textDocument/foldingRange") do
        counter += 1
      end
    end

    assert_equal(1, counter)

    # After the entry in the storage is updated, the cache is invalidated
    @store.set(uri: uri, source: "def bar; end", version: 1)
    5.times do
      @store.cache_fetch(uri, "textDocument/foldingRange") do
        counter += 1
      end
    end

    assert_equal(2, counter)
  end

  def test_push_edits
    uri = URI("file:///foo/bar.rb")
    @store.set(uri: uri, source: +"def bar; end", version: 1)

    # Write puts 'a' in incremental edits
    @store.push_edits(
      uri: uri,
      edits: [{ range: { start: { line: 0, character: 8 }, end: { line: 0, character: 8 } }, text: " " }],
      version: 2,
    )
    @store.push_edits(
      uri: uri,
      edits: [{ range: { start: { line: 0, character: 9 }, end: { line: 0, character: 9 } }, text: "p" }],
      version: 3,
    )
    @store.push_edits(
      uri: uri,
      edits: [{ range: { start: { line: 0, character: 10 }, end: { line: 0, character: 10 } }, text: "u" }],
      version: 4,
    )
    @store.push_edits(
      uri: uri,
      edits: [{ range: { start: { line: 0, character: 11 }, end: { line: 0, character: 11 } }, text: "t" }],
      version: 5,
    )
    @store.push_edits(
      uri: uri,
      edits: [{ range: { start: { line: 0, character: 12 }, end: { line: 0, character: 12 } }, text: "s" }],
      version: 6,
    )
    @store.push_edits(
      uri: uri,
      edits: [{ range: { start: { line: 0, character: 13 }, end: { line: 0, character: 13 } }, text: " " }],
      version: 7,
    )
    @store.push_edits(
      uri: uri,
      edits: [{ range: { start: { line: 0, character: 14 }, end: { line: 0, character: 14 } }, text: "'" }],
      version: 8,
    )
    @store.push_edits(
      uri: uri,
      edits: [{ range: { start: { line: 0, character: 15 }, end: { line: 0, character: 15 } }, text: "a" }],
      version: 9,
    )
    @store.push_edits(
      uri: uri,
      edits: [{ range: { start: { line: 0, character: 16 }, end: { line: 0, character: 16 } }, text: "'" }],
      version: 10,
    )
    @store.push_edits(
      uri: uri,
      edits: [{ range: { start: { line: 0, character: 17 }, end: { line: 0, character: 17 } }, text: ";" }],
      version: 11,
    )

    assert_equal(
      RubyLsp::Document.new(source: "def bar; puts 'a'; end", version: 1, uri: URI("file://foo.rb")),
      @store.get(uri),
    )
  end
end
