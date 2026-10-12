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

  def test_finds_references_in_a_workspace_path_with_glob_metacharacters
    Dir.mktmpdir do |dir|
      # `[id]` and `{slug}` are `Dir.glob` metacharacters, so interpolating the workspace path into the pattern
      # silently matches nothing and no reference is ever collected from disk
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

      locations = RubyLsp::Requests::References.new(
        global_state,
        RubyLsp::Store.new(global_state),
        document,
        { position: { line: 0, character: 6 } },
      ).perform

      assert_includes(
        locations.map(&:uri),
        URI::Generic.from_path(path: reference_path).to_s,
      )
    end
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
