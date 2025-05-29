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

  def test_finds_local_var_references
    refs = find_references("test/fixtures/local_var_examples.rb", { line: 2, character: 2 }).map do |ref|
      ref.range.start.line
    end

    assert_equal([2, 4, 6, 8, 10, 12], refs)
  end

  def test_finds_local_var_references_in_nested_scopes
    refs = find_references("test/fixtures/local_var_examples.rb", { line: 20, character: 2 }).map do |ref|
      ref.range.start.line
    end

    assert_equal([20, 22, 23], refs)
  end

  def test_finds_local_var_references_in_nested_scopes_position_in_block_args
    refs = find_references("test/fixtures/local_var_examples.rb", { line: 22, character: 12 }).map do |ref|
      ref.range.start.line
    end

    assert_equal([22, 23], refs)
  end

  private

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

    RubyLsp::Requests::References.new(
      global_state,
      store,
      document,
      { position: position },
    ).perform
  end
end
