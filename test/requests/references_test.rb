# typed: true
# frozen_string_literal: true

require "test_helper"

class ReferencesTest < Minitest::Test
  MULTIBYTE_SOURCE = <<~RUBY
    class Foo
      def self.helper
        1
      end
      def self.run
        s = "é😀"; Foo.helper
      end
    end
  RUBY

  def test_finds_constant_references
    refs = find_references("test/fixtures/rename_me.rb", { line: 0, character: 6 }).map do |ref|
      ref.range.start.line
    end

    assert_equal([0, 3], refs)
  end

  def test_finds_method_references_with_utf16_positions
    # `é` takes 2 bytes and 1 UTF-16 code unit. `😀` takes 4 bytes and 2 UTF-16 code units
    refs = find_references_in_source(MULTIBYTE_SOURCE, { line: 1, character: 11 }, "utf-16").map do |ref|
      { start: ref.range.start.to_hash, end: ref.range.end.to_hash }
    end

    assert_equal(
      [
        { start: { line: 1, character: 11 }, end: { line: 1, character: 17 } },
        { start: { line: 5, character: 19 }, end: { line: 5, character: 25 } },
      ],
      refs,
    )
  end

  def test_finds_method_references_with_utf8_positions
    # UTF-8 code units are bytes
    refs = find_references_in_source(MULTIBYTE_SOURCE, { line: 1, character: 11 }, "utf-8").map do |ref|
      { start: ref.range.start.to_hash, end: ref.range.end.to_hash }
    end

    assert_equal(
      [
        { start: { line: 1, character: 11 }, end: { line: 1, character: 17 } },
        { start: { line: 5, character: 22 }, end: { line: 5, character: 28 } },
      ],
      refs,
    )
  end

  private

  def find_references_in_source(source, position, position_encoding)
    uri = URI("file:///fake/multibyte.rb")
    global_state = RubyLsp::GlobalState.new
    global_state.apply_options({ capabilities: { general: { positionEncodings: [position_encoding] } } })
    global_state.index.index_single(uri, source)

    store = RubyLsp::Store.new(global_state)
    store.set(uri: uri, source: source, version: 1, language_id: :ruby)

    RubyLsp::Requests::References.new(
      global_state,
      store,
      store.get(uri), #: as RubyLsp::RubyDocument
      { position: position },
    ).perform.select { |location| location.uri == uri.to_s }
  end

  def find_references(fixture_path, position)
    source = File.read(fixture_path)
    path = File.expand_path(fixture_path)
    global_state = RubyLsp::GlobalState.new
    global_state.index.index_single(URI::Generic.from_path(path: path), source)

    store = RubyLsp::Store.new(global_state)
    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI::Generic.from_path(path: path),
      global_state: global_state,
    )

    # In addition to glob files from the workspace, we also want to test references collection from the store
    store.set(uri: URI::Generic.from_path(path: path), source: source, version: 1, language_id: :ruby)

    RubyLsp::Requests::References.new(
      global_state,
      store,
      document,
      { position: position },
    ).perform
  end
end
