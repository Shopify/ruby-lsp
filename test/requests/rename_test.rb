# typed: true
# frozen_string_literal: true

require "test_helper"

class RenameTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@tmp_dir)
  end

  def test_renaming_a_constant
    source = <<~RUBY
      class RenameMe
      end

      RenameMe
    RUBY

    result, document = perform_rename(
      source,
      position: { line: 0, character: 7 },
      new_name: "Article",
      file_name: "rename_me.rb",
    )

    apply_edits(result, document)

    assert_equal(<<~RUBY, document.source)
      class Article
      end

      Article
    RUBY

    assert_file_renamed(result, from: "rename_me.rb", to: "article.rb")
  end

  def test_renaming_a_complex_compact_style_constant
    source = <<~RUBY
      module Foo
        module Bar; end
      end

      module Baz
        include Foo

        class Bar::RenameMe
        end
      end

      Foo::Bar::RenameMe
    RUBY

    result, document = perform_rename(
      source,
      position: { line: 6, character: 13 },
      new_name: "Article",
    )

    apply_edits(result, document)

    assert_equal(<<~RUBY, document.source)
      module Foo
        module Bar; end
      end

      module Baz
        include Foo

        class Bar::Article
        end
      end

      Foo::Bar::Article
    RUBY
  end

  def test_renaming_a_method_receiver
    source = <<~RUBY
      class Foo
      end

      class Bar
        def Foo.qux
        end
      end
    RUBY

    result, document = perform_rename(
      source,
      position: { line: 4, character: 6 },
      new_name: "Zip",
    )

    apply_edits(result, document)

    assert_equal(<<~RUBY, document.source)
      class Zip
      end

      class Bar
        def Zip.qux
        end
      end
    RUBY
  end

  def test_renaming_conflict
    source = <<~RUBY
      class RenameMe
      end

      RenameMe
    RUBY

    assert_raises(RubyLsp::Requests::Rename::InvalidNameError) do
      perform_rename(source, position: { line: 3, character: 0 }, new_name: "Conflicting") do |graph|
        graph.index_source(
          URI::Generic.from_path(path: File.join(@tmp_dir, "conflicting.rb")).to_s,
          "class Conflicting\nend\n",
          "ruby",
        )
      end
    end
  end

  def test_renaming_across_unsaved_files
    source = <<~RUBY
      class RenameMe
      end

      RenameMe
    RUBY

    untitled_uri = URI("untitled:Untitled-1")
    untitled_source = <<~RUBY
      class RenameMe
      end
    RUBY

    result, = perform_rename(source, position: { line: 3, character: 0 }, new_name: "NewMe") do |graph, store|
      graph.index_source(untitled_uri.to_s, untitled_source, "ruby")
      store.set(uri: untitled_uri, source: untitled_source, version: 1, language_id: :ruby)
    end

    untitled_change = result.document_changes.find do |c|
      c.is_a?(RubyLsp::Interface::TextDocumentEdit) && c.text_document.uri == untitled_uri.to_s
    end
    refute_nil(untitled_change)
    assert_equal("NewMe", untitled_change.edits[0].new_text)
  end

  private

  #: (String, position: Hash[Symbol, Integer], new_name: String, ?file_name: String) ?{ (Rubydex::Graph, RubyLsp::Store) -> void } -> [RubyLsp::Interface::WorkspaceEdit, RubyLsp::RubyDocument]
  def perform_rename(source, position:, new_name:, file_name: "test.rb", &block)
    path = File.join(@tmp_dir, file_name)
    File.write(path, source)
    uri = URI::Generic.from_path(path: path)

    global_state = RubyLsp::GlobalState.new
    global_state.apply_options({
      workspaceFolders: [{ uri: URI::Generic.from_path(path: @tmp_dir).to_s }],
      capabilities: {
        workspace: {
          workspaceEdit: {
            resourceOperations: ["rename"],
          },
        },
      },
    })

    graph = global_state.graph
    store = RubyLsp::Store.new(global_state)
    graph.index_source(uri.to_s, source, "ruby")

    block&.call(graph, store)

    graph.resolve

    document = RubyLsp::RubyDocument.new(
      source: source.dup,
      version: 1,
      uri: uri,
      global_state: global_state,
    )

    result = RubyLsp::Requests::Rename.new(
      global_state,
      store,
      document,
      { position: position, newName: new_name },
    ).perform #: as !nil

    [result, document]
  end

  #: (RubyLsp::Interface::WorkspaceEdit result, RubyLsp::RubyDocument document) -> void
  def apply_edits(result, document)
    result.document_changes.each do |change|
      next unless change.is_a?(RubyLsp::Interface::TextDocumentEdit)
      next unless change.text_document.uri == document.uri.to_s

      document.push_edits(
        change.edits.map do |edit|
          { range: edit.range.to_hash.transform_values(&:to_hash), text: edit.new_text }
        end,
        version: 2,
      )
    end
  end

  #: (RubyLsp::Interface::WorkspaceEdit result, from: String, to: String) -> void
  def assert_file_renamed(result, from:, to:)
    file_rename = result.document_changes.find { |c| c.is_a?(RubyLsp::Interface::RenameFile) }
    refute_nil(file_rename, "Expected a file rename operation")
    assert(file_rename.old_uri.end_with?(from), "Expected old_uri to end with '#{from}', got '#{file_rename.old_uri}'")
    assert(file_rename.new_uri.end_with?(to), "Expected new_uri to end with '#{to}', got '#{file_rename.new_uri}'")
  end
end
