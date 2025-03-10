# typed: true
# frozen_string_literal: true

require "test_helper"

class GoToRelevantFileTest < Minitest::Test
  def test_when_input_is_test_file_returns_array_of_implementation_file_locations
    stub_glob_pattern("**/go_to_relevant_file.rb", ["lib/ruby_lsp/requests/go_to_relevant_file.rb"])

    test_file_path = "/workspace/test/requests/go_to_relevant_file_test.rb"
    expected = ["/workspace/lib/ruby_lsp/requests/go_to_relevant_file.rb"]

    result = RubyLsp::Requests::GoToRelevantFile.new(test_file_path, "/workspace").perform
    assert_equal(expected, result)
  end

  def test_when_input_is_implementation_file_returns_array_of_test_file_locations
    pattern =
      "**/{{test_,spec_,integration_test_}go_to_relevant_file,go_to_relevant_file{_test,_spec,_integration_test}}.rb"
    stub_glob_pattern(pattern, ["test/requests/go_to_relevant_file_test.rb"])

    impl_path = "/workspace/lib/ruby_lsp/requests/go_to_relevant_file.rb"
    expected = ["/workspace/test/requests/go_to_relevant_file_test.rb"]

    result = RubyLsp::Requests::GoToRelevantFile.new(impl_path, "/workspace").perform
    assert_equal(expected, result)
  end

  def test_return_all_file_locations_that_have_the_same_highest_coefficient
    pattern = "**/{{test_,spec_,integration_test_}some_feature,some_feature{_test,_spec,_integration_test}}.rb"
    matches = [
      "test/unit/some_feature_test.rb",
      "test/integration/some_feature_test.rb",
    ]
    stub_glob_pattern(pattern, matches)

    impl_path = "/workspace/lib/ruby_lsp/requests/some_feature.rb"
    expected = [
      "/workspace/test/unit/some_feature_test.rb",
      "/workspace/test/integration/some_feature_test.rb",
    ]

    result = RubyLsp::Requests::GoToRelevantFile.new(impl_path, "/workspace").perform
    assert_equal(expected.sort, result.sort)
  end

  def test_return_empty_array_when_no_filename_matches
    pattern = "**/{{test_,spec_,integration_test_}nonexistent_file,nonexistent_file{_test,_spec,_integration_test}}.rb"
    stub_glob_pattern(pattern, [])

    file_path = "/workspace/lib/ruby_lsp/requests/nonexistent_file.rb"
    result = RubyLsp::Requests::GoToRelevantFile.new(file_path, "/workspace").perform
    assert_empty(result)
  end

  def test_it_finds_implementation_when_file_has_test_suffix
    stub_glob_pattern("**/feature.rb", ["lib/feature.rb"])

    test_path = "/workspace/test/feature_test.rb"
    expected = ["/workspace/lib/feature.rb"]

    result = RubyLsp::Requests::GoToRelevantFile.new(test_path, "/workspace").perform
    assert_equal(expected, result)
  end

  def test_it_finds_implementation_when_file_has_spec_suffix
    stub_glob_pattern("**/feature.rb", ["lib/feature.rb"])

    test_path = "/workspace/spec/feature_spec.rb"
    expected = ["/workspace/lib/feature.rb"]

    result = RubyLsp::Requests::GoToRelevantFile.new(test_path, "/workspace").perform
    assert_equal(expected, result)
  end

  def test_it_finds_implementation_when_file_has_integration_test_suffix
    stub_glob_pattern("**/feature.rb", ["lib/feature.rb"])

    test_path = "/workspace/test/feature_integration_test.rb"
    expected = ["/workspace/lib/feature.rb"]

    result = RubyLsp::Requests::GoToRelevantFile.new(test_path, "/workspace").perform
    assert_equal(expected, result)
  end

  def test_it_finds_implementation_when_file_has_test_prefix
    stub_glob_pattern("**/feature.rb", ["lib/feature.rb"])

    test_path = "/workspace/test/test_feature.rb"
    expected = ["/workspace/lib/feature.rb"]

    result = RubyLsp::Requests::GoToRelevantFile.new(test_path, "/workspace").perform
    assert_equal(expected, result)
  end

  def test_it_finds_implementation_when_file_has_spec_prefix
    stub_glob_pattern("**/feature.rb", ["lib/feature.rb"])

    test_path = "/workspace/test/spec_feature.rb"
    expected = ["/workspace/lib/feature.rb"]

    result = RubyLsp::Requests::GoToRelevantFile.new(test_path, "/workspace").perform
    assert_equal(expected, result)
  end

  def test_it_finds_implementation_when_file_has_integration_test_prefix
    stub_glob_pattern("**/feature.rb", ["lib/feature.rb"])

    test_path = "/workspace/test/integration_test_feature.rb"
    expected = ["/workspace/lib/feature.rb"]

    result = RubyLsp::Requests::GoToRelevantFile.new(test_path, "/workspace").perform
    assert_equal(expected, result)
  end

  def test_it_finds_tests_for_implementation
    pattern = "**/{{test_,spec_,integration_test_}feature,feature{_test,_spec,_integration_test}}.rb"
    stub_glob_pattern(pattern, ["test/feature_test.rb"])

    impl_path = "/workspace/lib/feature.rb"
    expected = ["/workspace/test/feature_test.rb"]

    result = RubyLsp::Requests::GoToRelevantFile.new(impl_path, "/workspace").perform
    assert_equal(expected, result)
  end

  def test_it_finds_specs_for_implementation
    pattern = "**/{{test_,spec_,integration_test_}feature,feature{_test,_spec,_integration_test}}.rb"
    stub_glob_pattern(pattern, ["spec/feature_spec.rb"])

    impl_path = "/workspace/lib/feature.rb"
    expected = ["/workspace/spec/feature_spec.rb"]

    result = RubyLsp::Requests::GoToRelevantFile.new(impl_path, "/workspace").perform
    assert_equal(expected, result)
  end

  def test_it_finds_integration_tests_for_implementation
    pattern = "**/{{test_,spec_,integration_test_}feature,feature{_test,_spec,_integration_test}}.rb"
    stub_glob_pattern(pattern, ["test/feature_integration_test.rb"])

    impl_path = "/workspace/lib/feature.rb"
    expected = ["/workspace/test/feature_integration_test.rb"]

    result = RubyLsp::Requests::GoToRelevantFile.new(impl_path, "/workspace").perform
    assert_equal(expected, result)
  end

  private

  def stub_glob_pattern(pattern, matches)
    Dir.stubs(:glob).with(pattern).returns(matches)
  end
end
