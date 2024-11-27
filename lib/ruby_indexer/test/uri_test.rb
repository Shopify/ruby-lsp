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
      assert_equal("/C:/some/windows/path/to/file.rb", uri.path)
    end

    def test_from_path_on_windows_with_lowercase_drive
      uri = URI::Generic.from_path(path: "c:/some/windows/path/to/file.rb")
      assert_equal("/c:/some/windows/path/to/file.rb", uri.path)
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
  end
end
