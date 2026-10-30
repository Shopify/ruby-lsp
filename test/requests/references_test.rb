# typed: true
# frozen_string_literal: true

require "test_helper"

class ReferencesTest < Minitest::Test
  def test_finds_constant_references
    refs = find_references("test/fixtures/rename_me.rb", { line: 0, character: 6 }).map do |ref|
      ref.range.start.line
    end

    assert_equal([0, 3], refs)
  end

  def test_finds_constant_references_from_its_declaration
    source = <<~RUBY
      module Flags
        BIG_DOMAIN = "big_domain"
      end

      Flags::BIG_DOMAIN

      module Flags
        BIG_DOMAIN
      end
    RUBY

    refs = find_references_in_source(source, { line: 1, character: 3 }).map { |ref| ref.range.start.line }

    assert_equal([1, 4, 7], refs)
  end

  def test_finds_constant_references_from_its_or_write_declaration
    source = <<~RUBY
      module Flags
        BIG_DOMAIN ||= "big_domain"
      end

      Flags::BIG_DOMAIN
    RUBY

    refs = find_references_in_source(source, { line: 1, character: 3 }).map { |ref| ref.range.start.line }

    assert_equal([1, 4], refs)
  end

  private

  def find_references_in_source(source, position)
    uri = URI::Generic.from_path(path: "/fake/references.rb")
    global_state = RubyLsp::GlobalState.new
    global_state.index.index_single(uri, source)

    store = RubyLsp::Store.new(global_state)
    store.set(uri: uri, source: source, version: 1, language_id: :ruby)
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: global_state)

    RubyLsp::Requests::References.new(global_state, store, document, { position: position }).perform
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
