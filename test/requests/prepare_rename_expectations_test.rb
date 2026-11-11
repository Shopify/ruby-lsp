# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class PrepareRenameExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::PrepareRename, "prepare_rename"

  def run_expectations(source)
    position = @__params&.any? ? @__params[:position] : default_position
    uri = URI("file://#{@_path}")
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)
    RubyLsp::Requests::PrepareRename.new(document, position).perform
  end

  def test_prepare_rename_for_local_variables
    source = <<~RUBY
      def foo(name, label:)
        value = name
        value
      end
    RUBY

    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: @global_state,
    )

    range = RubyLsp::Requests::PrepareRename.new(document, { line: 2, character: 3 }).perform #: as !nil
    assert_equal({ line: 2, character: 2 }, range.start.to_hash)
    assert_equal({ line: 2, character: 7 }, range.end.to_hash)

    range = RubyLsp::Requests::PrepareRename.new(document, { line: 0, character: 9 }).perform #: as !nil
    assert_equal({ line: 0, character: 8 }, range.start.to_hash)
    assert_equal({ line: 0, character: 12 }, range.end.to_hash)

    # Keyword parameters are part of the method's signature, so they can't be renamed locally
    assert_nil(RubyLsp::Requests::PrepareRename.new(document, { line: 0, character: 15 }).perform)
  end

  private

  def default_position
    { line: 0, character: 0 }
  end
end
