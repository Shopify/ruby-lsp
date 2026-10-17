# typed: true
# frozen_string_literal: true

require "test_helper"

class RenameTest < Minitest::Test
  def test_renaming_a_class_updates_require_relative_paths
    Dir.mktmpdir do |workspace|
      lib_dir = File.join(workspace, "lib")
      FileUtils.mkdir_p(lib_dir)

      store_path = File.join(lib_dir, "store.rb")
      store_source = "class Store; end\n"
      File.write(store_path, store_source)

      use_path = File.join(lib_dir, "use.rb")
      use_source = <<~RUBY
        require_relative "store"
        Store.new
        "require_relative 'store'"
      RUBY
      File.write(use_path, use_source)

      global_state = RubyLsp::GlobalState.new
      global_state.apply_options({
        workspaceFolders: [{ uri: URI::Generic.from_path(path: workspace).to_s }],
        capabilities: {
          workspace: {
            workspaceEdit: {
              resourceOperations: ["rename"],
            },
          },
        },
      })

      store_uri = URI::Generic.from_path(path: store_path)
      use_uri = URI::Generic.from_path(path: use_path)
      global_state.index.index_single(store_uri, store_source)
      global_state.index.index_single(use_uri, use_source)

      document = RubyLsp::RubyDocument.new(
        source: store_source,
        version: 1,
        uri: store_uri,
        global_state: global_state,
      )

      workspace_edit = RubyLsp::Requests::Rename.new(
        global_state,
        RubyLsp::Store.new(global_state),
        document,
        { position: { line: 0, character: 7 }, newName: "Shop" },
      ).perform #: as !nil

      use_edit = workspace_edit.document_changes.find do |change|
        change.is_a?(RubyLsp::Interface::TextDocumentEdit) && change.text_document.uri == use_uri.to_s
      end

      assert_includes(use_edit.edits.map(&:new_text), "Shop")
      assert_equal(1, use_edit.edits.count { |edit| edit.new_text == "shop" })
    end
  end

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
