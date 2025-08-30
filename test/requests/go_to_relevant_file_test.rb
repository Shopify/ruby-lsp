# typed: true
# frozen_string_literal: true

require "test_helper"

class GoToRelevantFileTest < Minitest::Test
  def setup
    @workspace = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@workspace)
  end

  def test_when_input_is_test_file_returns_array_of_implementation_file_locations
    Dir.chdir(@workspace) do
      lib_dir  = File.join(@workspace, "lib/ruby_lsp/requests")
      test_dir = File.join(@workspace, "test/requests")
      FileUtils.mkdir_p(lib_dir)
      FileUtils.mkdir_p(test_dir)

      impl_file = File.join(lib_dir, "go_to_relevant_file.rb")
      test_file = File.join(test_dir, "go_to_relevant_file_test.rb")
      File.write(impl_file, "# impl")
      File.write(test_file, "# test")

      result = RubyLsp::Requests::GoToRelevantFile.new(test_file, @workspace).perform
      assert_equal([impl_file], result)
    end
  end

  def test_when_input_is_implementation_file_returns_array_of_test_file_locations
    Dir.chdir(@workspace) do
      lib_dir  = File.join(@workspace, "lib/ruby_lsp/requests")
      test_dir = File.join(@workspace, "test/requests")
      FileUtils.mkdir_p(lib_dir)
      FileUtils.mkdir_p(test_dir)

      impl_file = File.join(lib_dir, "go_to_relevant_file.rb")
      test_file = File.join(test_dir, "go_to_relevant_file_test.rb")
      File.write(impl_file, "# impl")
      File.write(test_file, "# test")

      result = RubyLsp::Requests::GoToRelevantFile.new(impl_file, @workspace).perform
      assert_equal([test_file], result)
    end
  end

  def test_return_empty_array_when_no_filename_matches
    Dir.chdir(@workspace) do
      lib_dir = File.join(@workspace, "lib/ruby_lsp/requests")
      FileUtils.mkdir_p(lib_dir)

      impl_file = File.join(lib_dir, "nonexistent_file.rb")
      File.write(impl_file, "# impl")

      result = RubyLsp::Requests::GoToRelevantFile.new(impl_file, @workspace).perform
      assert_empty(result)
    end
  end

  def test_it_finds_multiple_matching_tests
    Dir.chdir(@workspace) do
      lib_dir   = File.join(@workspace, "lib/ruby_lsp/requests")
      test_root = File.join(@workspace, "test") # ensure top-level test dir exists
      test_unit = File.join(test_root, "unit")
      test_int  = File.join(test_root, "integration")

      FileUtils.mkdir_p(lib_dir)
      FileUtils.mkdir_p(test_unit)
      FileUtils.mkdir_p(test_int)

      impl_file = File.join(lib_dir, "some_feature.rb")
      unit_test = File.join(test_unit, "some_feature_test.rb")
      int_test  = File.join(test_int, "some_feature_test.rb")
      [impl_file, unit_test, int_test].each { |f| File.write(f, "# file") }

      result = RubyLsp::Requests::GoToRelevantFile.new(impl_file, @workspace).perform

      assert_equal(
        [unit_test, int_test].sort,
        result.sort,
      )
    end
  end
end
