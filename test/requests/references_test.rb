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

  def test_finds_constant_references_from_constant_write
    source = <<~RUBY
      module ReferencesTestNamespace
        class Klass
          CONSTANT = 1
          CONSTANT
        end
      end

      ReferencesTestNamespace::Klass::CONSTANT
    RUBY

    refs = find_references_in_source(source, { line: 2, character: 4 }).map do |ref|
      ref.range.start.line
    end

    assert_equal([2, 3, 7], refs)
  end

  def test_finds_constant_references_from_constant_or_write
    source = <<~RUBY
      module ReferencesTestNamespace
        CONSTANT ||= 1
      end

      ReferencesTestNamespace::CONSTANT
    RUBY

    refs = find_references_in_source(source, { line: 1, character: 2 }).map do |ref|
      ref.range.start.line
    end

    assert_equal([1, 4], refs)
  end

  def test_finds_constant_references_from_constant_operator_write
    source = <<~RUBY
      module ReferencesTestNamespace
        CONSTANT = 1
        CONSTANT += 1
      end
    RUBY

    refs = find_references_in_source(source, { line: 2, character: 2 }).map do |ref|
      ref.range.start.line
    end

    assert_equal([1, 2], refs)
  end

  def test_finds_constant_references_from_constant_target
    source = <<~RUBY
      module ReferencesTestNamespace
        FIRST, SECOND = 1, 2
      end

      ReferencesTestNamespace::SECOND
    RUBY

    refs = find_references_in_source(source, { line: 1, character: 9 }).map do |ref|
      [ref.range.start.line, ref.range.start.character]
    end

    assert_equal([[1, 9], [4, 0]], refs)
  end

  private

  def find_references(fixture_path, position)
    path = File.expand_path(fixture_path)
    find_references_in_source(File.read(fixture_path), position, URI::Generic.from_path(path: path))
  end

  def find_references_in_source(source, position, uri = URI::Generic.from_path(path: "/fake.rb"))
    global_state = RubyLsp::GlobalState.new
    global_state.index.index_single(uri, source)

    store = RubyLsp::Store.new(global_state)
    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: uri,
      global_state: global_state,
    )

    # In addition to glob files from the workspace, we also want to test references collection from the store
    store.set(uri: uri, source: source, version: 1, language_id: :ruby)

    RubyLsp::Requests::References.new(
      global_state,
      store,
      document,
      { position: position },
    ).perform
  end
end
