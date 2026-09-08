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

  def test_collects_text_edits_in_a_workspace_path_with_glob_metacharacters
    Dir.mktmpdir do |dir|
      # `[id]` and `{slug}` are `Dir.glob` metacharacters, so interpolating the workspace path into the pattern
      # silently matches nothing and references in other files are never renamed
      workspace = File.join(dir, "[id]", "{slug}")
      FileUtils.mkdir_p(workspace)

      declaration_path = File.join(workspace, "article.rb")
      reference_path = File.join(workspace, "consumer.rb")
      File.write(declaration_path, "class Article\nend\n")
      File.write(reference_path, "Article\n")

      global_state = RubyLsp::GlobalState.new
      global_state.apply_options({
        workspaceFolders: [{ uri: URI::Generic.from_path(path: workspace).to_s }],
      })

      source = File.read(declaration_path)
      uri = URI::Generic.from_path(path: declaration_path)
      global_state.index.index_single(uri, source)

      document = RubyLsp::RubyDocument.new(
        source: source,
        version: 1,
        uri: uri,
        global_state: global_state,
      )

      workspace_edit = RubyLsp::Requests::Rename.new(
        global_state,
        RubyLsp::Store.new(global_state),
        document,
        { position: { line: 0, character: 6 }, newName: "Post" },
      ).perform #: as !nil

      reference_uri = URI::Generic.from_path(path: reference_path).to_s
      assert_includes(workspace_edit.changes.keys, reference_uri)
      assert_equal("Post", workspace_edit.changes[reference_uri].first.new_text)
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
