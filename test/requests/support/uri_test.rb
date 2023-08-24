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

    def test_plus_signs_are_properly_unescaped
      path = "/opt/rubies/3.3.0/lib/ruby/3.3.0+0/pathname.rb"
      uri = URI::Generic.from_path(path: path)
      assert_equal(path, uri.to_standardized_path)
    end

    def test_from_path_with_fragment
      uri = URI::Generic.from_path(path: "/some/unix/path/to/file.rb", fragment: "L1,3-2,9")
      assert_equal("file:///some/unix/path/to/file.rb#L1,3-2,9", uri.to_s)
    end
  end
end
