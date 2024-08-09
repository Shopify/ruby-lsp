# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyIndexer
  class UriTest < Minitest::Test
    def test_from_path_on_unix
      uri = ResourceUri.new(path: "/some/unix/path/to/file.rb")
      assert_equal("/some/unix/path/to/file.rb", uri.path)
    end

    def test_from_path_on_windows
      uri = ResourceUri.new(path: "C:/some/windows/path/to/file.rb")
      assert_equal("/C:/some/windows/path/to/file.rb", uri.path)
    end

    def test_from_path_on_windows_with_lowercase_drive
      uri = ResourceUri.new(path: "c:/some/windows/path/to/file.rb")
      assert_equal("/c:/some/windows/path/to/file.rb", uri.path)
    end

    def test_to_standardized_path_on_unix
      uri = ResourceUri.new(path: "/some/unix/path/to/file.rb")
      assert_equal(uri.path, uri.to_standardized_path)
    end

    def test_to_standardized_path_on_windows
      uri = ResourceUri.new(path: "C:/some/windows/path/to/file.rb")
      assert_equal("C:/some/windows/path/to/file.rb", uri.to_standardized_path)
    end

    def test_to_standardized_path_on_windows_with_lowercase_drive
      uri = ResourceUri.new(path: "c:/some/windows/path/to/file.rb")
      assert_equal("c:/some/windows/path/to/file.rb", uri.to_standardized_path)
    end

    def test_to_standardized_path_on_windows_with_received_uri
      uri = URI("file:///c%3A/some/windows/path/to/file.rb")
      assert_equal("c:/some/windows/path/to/file.rb", uri.to_standardized_path)
    end

    def test_plus_signs_are_properly_unescaped
      path = "/opt/rubies/3.3.0/lib/ruby/3.3.0+0/pathname.rb"
      uri = ResourceUri.new(path: path)
      assert_equal(path, uri.to_standardized_path)
    end

    def test_from_path_with_fragment
      uri = ResourceUri.new(path: "/some/unix/path/to/file.rb", fragment: "L1,3-2,9")
      assert_equal("file:///some/unix/path/to/file.rb", uri.to_s)
      assert_equal("file:///some/unix/path/to/file.rb#L1,3-2,9", uri.to_s_with_fragment)
    end

    def test_from_path_windows_long_file_paths
      uri = ResourceUri.new(path: "//?/C:/hostedtoolcache/windows/Ruby/3.3.1/x64/lib/ruby/3.3.0/open-uri.rb")
      assert_equal("C:/hostedtoolcache/windows/Ruby/3.3.1/x64/lib/ruby/3.3.0/open-uri.rb", uri.to_standardized_path)
    end
  end
end
