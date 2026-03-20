# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyIndexer
  class URITest < Minitest::Test
    def test_from_path_on_unix
      uri = URI::Generic.from_path(path: "/some/unix/path/to/file.rb")
      assert_equal("/some/unix/path/to/file.rb", uri.path)
    end

    def test_from_path_on_windows
      uri = URI::Generic.from_path(path: "C:/some/windows/path/to/file.rb")
      assert_equal("/C%3A/some/windows/path/to/file.rb", uri.path)
    end

    def test_from_path_on_windows_with_lowercase_drive
      uri = URI::Generic.from_path(path: "c:/some/windows/path/to/file.rb")
      assert_equal("/c%3A/some/windows/path/to/file.rb", uri.path)
    end

    def test_to_standardized_path_on_unix
      uri = URI::Generic.from_path(path: "/some/unix/path/to/file.rb")
      assert_equal(uri.path, uri.to_standardized_path)
    end

    def test_to_standardized_path_on_windows
      uri = URI::Generic.from_path(path: "C:/some/windows/path/to/file.rb")
      assert_equal("C:/some/windows/path/to/file.rb", uri.to_standardized_path)
    end

    def test_to_standardized_path_on_windows_with_lowercase_drive
      uri = URI::Generic.from_path(path: "c:/some/windows/path/to/file.rb")
      assert_equal("c:/some/windows/path/to/file.rb", uri.to_standardized_path)
    end

    def test_to_standardized_path_on_windows_with_received_uri
      uri = URI("file:///c%3A/some/windows/path/to/file.rb")
      assert_equal("c:/some/windows/path/to/file.rb", uri.to_standardized_path)
    end

    def test_plus_signs_are_properly_unescaped
      path = "/opt/rubies/3.3.0/lib/ruby/3.3.0+0/pathname.rb"
      uri = URI::Generic.from_path(path: path)
      assert_equal(path, uri.to_standardized_path)
    end

    def test_from_path_with_fragment
      uri = URI::Generic.from_path(path: "/some/unix/path/to/file.rb", fragment: "L1,3-2,9")
      assert_equal("file:///some/unix/path/to/file.rb#L1,3-2,9", uri.to_s)
    end

    def test_from_path_windows_long_file_paths
      uri = URI::Generic.from_path(path: "//?/C:/hostedtoolcache/windows/Ruby/3.3.1/x64/lib/ruby/3.3.0/open-uri.rb")
      assert_equal("C:/hostedtoolcache/windows/Ruby/3.3.1/x64/lib/ruby/3.3.0/open-uri.rb", uri.to_standardized_path)
    end

    def test_from_path_computes_require_path_when_load_path_entry_is_given
      uri = URI::Generic.from_path(path: "/some/unix/path/to/file.rb", load_path_entry: "/some/unix/path")
      assert_equal("to/file", uri.require_path)
    end

    def test_allows_adding_require_path_with_load_path_entry
      uri = URI::Generic.from_path(path: "/some/unix/path/to/file.rb")
      assert_nil(uri.require_path)

      uri.add_require_path_from_load_entry("/some/unix/path")
      assert_equal("to/file", uri.require_path)
    end

    def test_from_path_escapes_colon_characters
      uri = URI::Generic.from_path(path: "c:/some/windows/path with/spaces/file.rb")
      assert_equal("c:/some/windows/path with/spaces/file.rb", uri.to_standardized_path)
      assert_equal("file:///c%3A/some/windows/path%20with/spaces/file.rb", uri.to_s)
    end

    def test_from_path_with_unicode_characters
      path = "/path/with/unicode/文件.rb"
      uri = URI::Generic.from_path(path: path)
      assert_equal(path, uri.to_standardized_path)
      assert_equal("file:///path/with/unicode/%E6%96%87%E4%BB%B6.rb", uri.to_s)
    end

    def test_from_path_with_brackets
      uri = URI::Generic.from_path(path: "/some/path/[id].rb")
      assert_match("%5B", uri.path)
      assert_match("%5D", uri.path)
      assert_equal("file:///some/path/%5Bid%5D.rb", uri.to_s)
    end

    def test_from_path_with_braces
      uri = URI::Generic.from_path(path: "/some/path/{slug}.rb")
      assert_match("%7B", uri.path)
      assert_match("%7D", uri.path)
      assert_equal("file:///some/path/%7Bslug%7D.rb", uri.to_s)
    end

    def test_round_trip_with_brackets
      path = "/some/path/[id].rb"
      uri = URI::Generic.from_path(path: path)
      assert_equal(path, uri.to_standardized_path)
    end

    def test_round_trip_with_braces
      path = "/some/path/{slug}.rb"
      uri = URI::Generic.from_path(path: path)
      assert_equal(path, uri.to_standardized_path)
    end

    def test_from_path_with_parentheses
      uri = URI::Generic.from_path(path: "/some/path/(id).rb")
      assert_equal("/some/path/(id).rb", uri.path)
      assert_equal("file:///some/path/(id).rb", uri.to_s)
    end

    def test_round_trip_with_parentheses
      path = "/some/path/(id).rb"
      uri = URI::Generic.from_path(path: path)
      assert_equal(path, uri.to_standardized_path)
    end

    def test_round_trip_with_spaces_inside_brackets
      path = "/some/path/[id page].rb"
      uri = URI::Generic.from_path(path: path)
      assert_equal(path, uri.to_standardized_path)
      assert_equal("file:///some/path/%5Bid%20page%5D.rb", uri.to_s)
    end

    def test_round_trip_with_spaces_inside_braces
      path = "/some/path/{slug name}.rb"
      uri = URI::Generic.from_path(path: path)
      assert_equal(path, uri.to_standardized_path)
      assert_equal("file:///some/path/%7Bslug%20name%7D.rb", uri.to_s)
    end

    def test_round_trip_with_spaces_inside_parentheses
      path = "/some/path/file (copy).rb"
      uri = URI::Generic.from_path(path: path)
      assert_equal(path, uri.to_standardized_path)
      assert_equal("file:///some/path/file%20(copy).rb", uri.to_s)
    end
  end
end
