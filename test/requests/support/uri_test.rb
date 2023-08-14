# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
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
  end
end
