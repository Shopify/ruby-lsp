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
      FileUtils.touch(impl_file)
      FileUtils.touch(test_file)

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
      FileUtils.touch(impl_file)
      FileUtils.touch(test_file)

      result = RubyLsp::Requests::GoToRelevantFile.new(impl_file, @workspace).perform
      assert_equal([test_file], result)
    end
  end

  def test_return_empty_array_when_no_filename_matches
    Dir.chdir(@workspace) do
      lib_dir = File.join(@workspace, "lib/ruby_lsp/requests")
      FileUtils.mkdir_p(lib_dir)

      impl_file = File.join(lib_dir, "nonexistent_file.rb")
      FileUtils.touch(impl_file)

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
      FileUtils.touch(impl_file)
      FileUtils.touch(unit_test)
      FileUtils.touch(int_test)

      result = RubyLsp::Requests::GoToRelevantFile.new(impl_file, @workspace).perform

      assert_equal(
        [unit_test, int_test].sort,
        result.sort,
      )
    end
  end

  def test_search_within_implementation_test_root
    Dir.chdir(@workspace) do
      lib_a_dir = File.join(@workspace, "a")
      lib_a_test_dir = File.join(@workspace, "a", "test")
      FileUtils.mkdir_p(lib_a_dir)
      FileUtils.mkdir_p(lib_a_test_dir)

      lib_b_dir = File.join(@workspace, "b")
      lib_b_test_dir = File.join(@workspace, "b", "test")
      FileUtils.mkdir_p(lib_b_dir)
      FileUtils.mkdir_p(lib_b_test_dir)

      impl_a_file = File.join(lib_a_dir, "implementation.rb")
      unit_a_test = File.join(lib_a_test_dir, "implementation_test.rb")

      impl_b_file = File.join(lib_b_dir, "implementation.rb")
      unit_b_test = File.join(lib_b_test_dir, "implementation_test.rb")

      FileUtils.touch(impl_a_file)
      FileUtils.touch(unit_a_test)
      FileUtils.touch(impl_b_file)
      FileUtils.touch(unit_b_test)

      result = RubyLsp::Requests::GoToRelevantFile.new(impl_a_file, @workspace).perform

      assert_equal(
        [unit_a_test].sort,
        result.sort,
      )
    end
  end

  def test_finds_tests_in_matching_subdirectory
    Dir.chdir(@workspace) do
      lib_dir = File.join(@workspace, "lib")
      test_root = File.join(@workspace, "test")
      test_subdir = File.join(test_root, "user")

      FileUtils.mkdir_p(lib_dir)
      FileUtils.mkdir_p(test_subdir)

      impl_file = File.join(lib_dir, "user.rb")
      test_file1 = File.join(test_subdir, "create_user_test.rb")
      test_file2 = File.join(test_subdir, "test_update_user.rb")

      FileUtils.touch(impl_file)
      FileUtils.touch(test_file1)
      FileUtils.touch(test_file2)

      result = RubyLsp::Requests::GoToRelevantFile.new(impl_file, @workspace).perform

      assert_equal(
        [test_file1, test_file2].sort,
        result.sort,
      )
    end
  end

  def test_finds_implementation_from_nested_test_file
    Dir.chdir(@workspace) do
      lib_dir = File.join(@workspace, "lib")
      test_root = File.join(@workspace, "test")
      test_subdir = File.join(test_root, "go_to_relevant_file")

      FileUtils.mkdir_p(lib_dir)
      FileUtils.mkdir_p(test_subdir)

      impl_file = File.join(lib_dir, "go_to_relevant_file.rb")
      test_file = File.join(test_subdir, "go_to_relevant_file_a_test.rb")

      FileUtils.touch(impl_file)
      FileUtils.touch(test_file)

      result = RubyLsp::Requests::GoToRelevantFile.new(test_file, @workspace).perform

      assert_equal([impl_file], result)
    end
  end
end
