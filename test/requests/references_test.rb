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

  def test_finds_references_from_constant_write_definition
    source = <<~RUBY
      class Foo
        BAR = 1
        BAR
      end

      Foo::BAR
    RUBY

    refs = find_references_for_source(source, { line: 1, character: 2 }).map do |ref|
      ref.range.start.line
    end

    assert_equal([1, 2, 5], refs)
  end

  def test_finds_references_from_constant_or_write_definition
    source = <<~RUBY
      class Foo
        BAR ||= 1
        BAR
      end

      Foo::BAR
    RUBY

    refs = find_references_for_source(source, { line: 1, character: 2 }).map do |ref|
      ref.range.start.line
    end

    assert_equal([1, 2, 5], refs)
  end

  def test_finds_references_from_constant_operator_write_definition
    source = <<~RUBY
      class Foo
        BAR = 1
        BAR += 2
        BAR
      end
    RUBY

    refs = find_references_for_source(source, { line: 2, character: 2 }).map do |ref|
      ref.range.start.line
    end

    assert_equal([1, 2, 3], refs)
  end

  def test_finds_references_from_constant_target_multi_write
    source = <<~RUBY
      CONST_A, CONST_B = 1, 2
      CONST_A
      CONST_B
    RUBY

    refs_a = find_references_for_source(source, { line: 0, character: 0 }).map do |ref|
      ref.range.start.line
    end
    assert_equal([0, 1], refs_a)

    refs_b = find_references_for_source(source, { line: 0, character: 9 }).map do |ref|
      ref.range.start.line
    end
    assert_equal([0, 2], refs_b)
  end

  def test_returns_empty_when_cursor_is_on_constant_assignment_value
    source = <<~RUBY
      FOO = 123
      FOO
    RUBY

    refs = find_references_for_source(source, { line: 0, character: 7 })
    assert_empty(refs)
  end

  private

  def find_references(fixture_path, position)
    source = File.read(fixture_path)
    path = File.expand_path(fixture_path)
    find_references_for_source(source, position, path: path)
  end

  def find_references_for_source(source, position, path: File.expand_path("test/fixtures/fake.rb"))
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
