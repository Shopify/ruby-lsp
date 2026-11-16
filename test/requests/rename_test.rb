# typed: true
# frozen_string_literal: true

require "test_helper"

class RenameTest < Minitest::Test
  def test_empty_diagnostics_for_ignored_file
    expected = <<~RUBY
      class Article
      end

      Article
    RUBY

    expect_renames(
      "test/fixtures/rename_me.rb",
      File.join("test", "fixtures", "article.rb"),
      expected,
      { line: 0, character: 7 },
      "Article",
    )
  end

  def test_renaming_conflict
    fixture_path = "test/fixtures/rename_me.rb"
    source = File.read(fixture_path)
    global_state = RubyLsp::GlobalState.new
    global_state.apply_options({
      capabilities: {
        workspace: {
          workspaceEdit: {
            resourceOperations: ["rename"],
          },
        },
      },
    })
    path = File.expand_path(fixture_path)
    global_state.index.index_single(URI::Generic.from_path(path: path), source)
    global_state.index.index_single(URI::Generic.from_path(path: "/fake.rb"), <<~RUBY)
      class Conflicting
      end
    RUBY

    store = RubyLsp::Store.new(global_state)
    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI::Generic.from_path(path: path),
      global_state: global_state,
    )

    assert_raises(RubyLsp::Requests::Rename::InvalidNameError) do
      RubyLsp::Requests::Rename.new(
        global_state,
        store,
        document,
        { position: { line: 3, character: 7 }, newName: "Conflicting" },
      ).perform
    end
  end

  def test_renaming_an_unsaved_symbol
    fixture_path = "test/fixtures/rename_me.rb"
    source = File.read(fixture_path)
    global_state = RubyLsp::GlobalState.new
    global_state.apply_options({
      capabilities: {
        workspace: {
          workspaceEdit: {
            resourceOperations: ["rename"],
          },
        },
      },
    })

    store = RubyLsp::Store.new(global_state)

    path = File.expand_path(fixture_path)
    global_state.index.index_single(URI::Generic.from_path(path: path), source)

    untitled_uri = URI("untitled:Untitled-1")
    untitled_source = <<~RUBY
      class RenameMe
      end
    RUBY
    global_state.index.index_single(untitled_uri, untitled_source)
    store.set(uri: untitled_uri, source: untitled_source, version: 1, language_id: :ruby)

    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI::Generic.from_path(path: path),
      global_state: global_state,
    )

    response = RubyLsp::Requests::Rename.new(
      global_state,
      store,
      document,
      { position: { line: 3, character: 7 }, newName: "NewMe" },
    ).perform #: as !nil

    untitled_change = response.document_changes[1]
    assert_equal("untitled:Untitled-1", untitled_change.text_document.uri)
    assert_equal("NewMe", untitled_change.edits[0].new_text)
  end

  def test_renaming_a_local_variable
    source = <<~RUBY
      def foo(items)
        total = 0
        items.each { |item| total += item }
        total
      end

      def bar
        total = 1
      end
    RUBY

    expected = <<~RUBY
      def foo(items)
        sum = 0
        items.each { |item| sum += item }
        sum
      end

      def bar
        total = 1
      end
    RUBY

    assert_equal(expected, rename_local(source, { line: 3, character: 2 }, "sum"))
  end

  def test_renaming_a_method_parameter
    source = <<~RUBY
      def foo(name, label = name)
        "\#{label}: \#{name}"
      end
    RUBY

    expected = <<~RUBY
      def foo(title, label = title)
        "\#{label}: \#{title}"
      end
    RUBY

    assert_equal(expected, rename_local(source, { line: 0, character: 8 }, "title"))
  end

  def test_renaming_a_local_used_as_a_shorthand_keeps_the_keys
    source = <<~RUBY
      name = "x"
      { name: }
      foo(name:)
    RUBY

    expected = <<~RUBY
      title = "x"
      { name: title }
      foo(name: title)
    RUBY

    assert_equal(expected, rename_local(source, { line: 0, character: 0 }, "title"))
  end

  def test_renaming_a_local_bound_by_a_hash_pattern_keeps_the_key
    source = <<~RUBY
      def foo(input)
        case input
        in { name: } then name
        end
      end
    RUBY

    expected = <<~RUBY
      def foo(input)
        case input
        in { name: matched } then matched
        end
      end
    RUBY

    assert_equal(expected, rename_local(source, { line: 2, character: 20 }, "matched"))
  end

  def test_renaming_a_regexp_named_capture
    source = <<~RUBY
      if /(?<year>\\d+)/ =~ date
        year
      end
    RUBY

    expected = <<~RUBY
      if /(?<release_year>\\d+)/ =~ date
        release_year
      end
    RUBY

    assert_equal(expected, rename_local(source, { line: 1, character: 2 }, "release_year"))
  end

  def test_renaming_a_local_after_multibyte_characters
    source = <<~RUBY
      greeting = "こんにちは"; puts greeting
    RUBY

    expected = <<~RUBY
      message = "こんにちは"; puts message
    RUBY

    assert_equal(expected, rename_local(source, { line: 0, character: 25 }, "message"))
  end

  def test_renaming_a_local_to_a_name_in_use_raises
    source = <<~RUBY
      def foo(other)
        value = 1
        [1].each { |n| value += n }
        helper
      end
    RUBY

    ["other", "n", "helper"].each do |new_name|
      assert_raises(RubyLsp::Requests::Rename::InvalidNameError) do
        rename_local(source, { line: 1, character: 2 }, new_name)
      end
    end
  end

  def test_renaming_a_local_to_an_invalid_name_raises
    source = <<~RUBY
      value = 1
    RUBY

    ["Value", "end", "1abc", "foo bar", "@value", "_1"].each do |new_name|
      assert_raises(RubyLsp::Requests::Rename::InvalidNameError) do
        rename_local(source, { line: 0, character: 0 }, new_name)
      end
    end
  end

  def test_renaming_a_keyword_parameter_raises
    source = <<~RUBY
      def foo(name:)
        name
      end
    RUBY

    error = assert_raises(RubyLsp::Requests::Rename::InvalidNameError) do
      rename_local(source, { line: 1, character: 2 }, "title")
    end
    assert_match(/Keyword parameters/, error.message)
  end

  private

  def rename_local(source, position, new_name)
    global_state = RubyLsp::GlobalState.new
    global_state.apply_options({ capabilities: { general: { positionEncodings: ["utf-16"] } } })
    store = RubyLsp::Store.new(global_state)
    document = RubyLsp::RubyDocument.new(
      source: source.dup,
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: global_state,
    )

    workspace_edit = RubyLsp::Requests::Rename.new(
      global_state,
      store,
      document,
      { position: position, newName: new_name },
    ).perform #: as !nil

    edits = workspace_edit.changes&.fetch("file:///fake.rb") || []
    # Edits are relative to the original source, so apply them from the end of the document backwards
    edits = edits.sort_by { |edit| [edit.range.start.line, edit.range.start.character] }.reverse
    document.push_edits(
      edits.map { |edit| { range: edit.range.to_hash.transform_values(&:to_hash), text: edit.new_text } },
      version: 2,
    )
    document.source
  end

  def expect_renames(fixture_path, new_fixture_path, expected, position, new_name)
    source = File.read(fixture_path)
    global_state = RubyLsp::GlobalState.new
    global_state.apply_options({
      capabilities: {
        workspace: {
          workspaceEdit: {
            resourceOperations: ["rename"],
          },
        },
      },
    })
    path = File.expand_path(fixture_path)
    global_state.index.index_single(URI::Generic.from_path(path: path), source)

    store = RubyLsp::Store.new(global_state)
    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI::Generic.from_path(path: path),
      global_state: global_state,
    )
    workspace_edit = RubyLsp::Requests::Rename.new(
      global_state,
      store,
      document,
      { position: position, newName: new_name },
    ).perform #: as !nil

    file_renames = workspace_edit.document_changes.filter_map do |text_edit_or_rename|
      next text_edit_or_rename unless text_edit_or_rename.is_a?(RubyLsp::Interface::TextDocumentEdit)

      document.push_edits(
        text_edit_or_rename.edits.map do |edit|
          { range: edit.range.to_hash.transform_values(&:to_hash), text: edit.new_text }
        end,
        version: 2,
      )
      nil
    end

    assert_equal(expected, document.source)
    assert_equal(File.expand_path(new_fixture_path), URI(file_renames.first.new_uri).to_standardized_path)
  end
end
