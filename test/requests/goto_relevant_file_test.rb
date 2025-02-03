# typed: true
# frozen_string_literal: true

require "test_helper"

class GotoRelevantFileTest < Minitest::Test
  def test_when_input_is_test_file_returns_array_of_source_file_locations
    test_file_path = File.join(Dir.pwd, "/test/requests/goto_relevant_file_test.rb")
    expected = [File.join(Dir.pwd, "/lib/ruby_lsp/requests/goto_relevant_file.rb")]

    result = RubyLsp::Requests::GotoRelevantFile.new(test_file_path).perform

    assert_equal(expected, result)
  end

  def test_input_is_source_file_returns_array_of_test_file_locations
    source_file_path = File.join(Dir.pwd, "/lib/ruby_lsp/requests/goto_relevant_file.rb")
    expected = [File.join(Dir.pwd, "/test/requests/goto_relevant_file_test.rb")]

    result = RubyLsp::Requests::GotoRelevantFile.new(source_file_path).perform

    assert_equal(expected, result)
  end
end
