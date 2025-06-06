# typed: true
# frozen_string_literal: true

require "test_helper"

class PrepareRenameTest < Minitest::Test
  def test_prepare_rename_for_constant
    fixture_path = "test/fixtures/rename_me.rb"
    source = File.read(fixture_path)
    global_state = RubyLsp::GlobalState.new
    global_state.apply_options({
      capabilities: {
        workspace: {
          workspaceEdit: {
            resourceOperations: ["prepareRename"],
          },
        },
      },
    })

    path = File.expand_path(fixture_path)
    global_state.index.index_single(URI::Generic.from_path(path: path), source)

    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI::Generic.from_path(path: path),
      global_state: global_state,
    )

    range = RubyLsp::Requests::PrepareRename.new(
      document,
      { line: 3, character: 0 },
    ).perform #: as !nil

    assert_equal({ line: 3, character: 0 }, range.start.attributes)
    assert_equal({ line: 3, character: 8 }, range.end.attributes)
  end

  def test_prepare_rename_for_local_variable
    fixture_path = "test/fixtures/local_variables.rb"
    source = File.read(fixture_path)
    global_state = RubyLsp::GlobalState.new
    global_state.apply_options({
      capabilities: {
        workspace: {
          workspaceEdit: {
            resourceOperations: ["prepareRename"],
          },
        },
      },
    })

    path = File.expand_path(fixture_path)
    global_state.index.index_single(URI::Generic.from_path(path: path), source)

    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI::Generic.from_path(path: path),
      global_state: global_state,
    )

    range = RubyLsp::Requests::PrepareRename.new(
      document,
      { line: 2, character: 2 },
    ).perform #: as !nil

    assert_equal({ line: 2, character: 2 }, range.start.attributes)
    assert_equal({ line: 2, character: 5 }, range.end.attributes)
  end
end
