# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class PrepareRenameExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::PrepareRename, "prepare_rename"

  def run_expectations(source)
    position = @__params&.any? ? @__params[:position] : default_position
    uri = URI("file://#{@_path}")
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri)
    RubyLsp::Requests::PrepareRename.new(document, position).perform
  end

  private

  def default_position
    { line: 0, character: 0 }
  end
end
