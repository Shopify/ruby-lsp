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
    global_state.index.index_single(RubyIndexer::IndexablePath.new(nil, path), source)
    global_state.index.index_single(RubyIndexer::IndexablePath.new(nil, "/fake.rb"), <<~RUBY)
      class Conflicting
      end
    RUBY

    store = RubyLsp::Store.new
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: URI::Generic.from_path(path: path))

    assert_raises(RubyLsp::Requests::Rename::InvalidNameError) do
      RubyLsp::Requests::Rename.new(
        global_state,
        store,
        document,
        { position: { line: 3, character: 7 }, newName: "Conflicting" },
      ).perform
    end
  end

  private

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
    global_state.index.index_single(RubyIndexer::IndexablePath.new(nil, path), source)

    store = RubyLsp::Store.new
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: URI::Generic.from_path(path: path))
    workspace_edit = T.must(
      RubyLsp::Requests::Rename.new(
        global_state,
        store,
        document,
        { position: position, newName: new_name },
      ).perform,
    )

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
