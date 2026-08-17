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

  def test_constant_definition
    source = <<~RUBY
      Foo = 1
      Bar, Baz = 2, 3
    RUBY
    uri = URI("file:///fake.rb")
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    range = RubyLsp::Requests::PrepareRename.new(
      document,
      { line: 0, character: 1 },
    ).perform #: as !nil

    assert_equal(0, range.start.line)
    assert_equal(0, range.start.character)
    assert_equal(0, range.end.line)
    assert_equal(3, range.end.character)

    range = RubyLsp::Requests::PrepareRename.new(
      document,
      { line: 1, character: 1 },
    ).perform #: as !nil

    assert_equal(1, range.start.line)
    assert_equal(0, range.start.character)
    assert_equal(1, range.end.line)
    assert_equal(3, range.end.character)
  end

  private

  def default_position
    { line: 0, character: 0 }
  end
end
