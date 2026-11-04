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

  def test_finds_local_variable_references_in_the_current_document
    source = <<~RUBY
      def foo(items)
        total = 0
        items.each { |item| total += item }
        puts(total)
      end

      def bar
        total = 1
      end
    RUBY

    refs = find_local_references(source, { line: 3, character: 7 }).map { |ref| range_tuple(ref.range) }
    assert_equal([[1, 2, 1, 7], [2, 22, 2, 27], [3, 7, 3, 12]], refs)
  end

  def test_local_variable_references_honor_include_declaration
    source = <<~RUBY
      def foo(name)
        name.upcase
        name
      end
    RUBY

    refs = find_local_references(source, { line: 2, character: 2 }, include_declaration: false)
    assert_equal([[1, 2, 1, 6], [2, 2, 2, 6]], refs.map { |ref| range_tuple(ref.range) })
  end

  def test_local_variable_in_call_arguments_is_not_treated_as_the_method
    source = <<~RUBY
      value = 1
      puts(value)
    RUBY

    refs = find_local_references(source, { line: 1, character: 6 })
    assert_equal([[0, 0, 0, 5], [1, 5, 1, 10]], refs.map { |ref| range_tuple(ref.range) })
    assert(refs.all? { |ref| ref.uri == "file:///fake.rb" })
  end

  def test_finds_local_variable_references_in_erb
    source = <<~ERB
      <% items.each do |item| %>
        <li><%= item.name %></li>
      <% end %>
    ERB

    global_state = RubyLsp::GlobalState.new
    document = RubyLsp::ERBDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///fake.erb"),
      global_state: global_state,
    )

    refs = RubyLsp::Requests::References.new(
      global_state,
      RubyLsp::Store.new(global_state),
      document,
      { position: { line: 1, character: 10 } },
    ).perform

    assert_equal([[0, 18, 0, 22], [1, 10, 1, 14]], refs.map { |ref| range_tuple(ref.range) })
  end

  private

  def find_local_references(source, position, include_declaration: true)
    global_state = RubyLsp::GlobalState.new
    store = RubyLsp::Store.new(global_state)
    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: global_state,
    )

    RubyLsp::Requests::References.new(
      global_state,
      store,
      document,
      { position: position, context: { includeDeclaration: include_declaration } },
    ).perform
  end

  def range_tuple(range)
    [range.start.line, range.start.character, range.end.line, range.end.character]
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
