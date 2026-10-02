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
      assert_equal("file:///some/path/%5Bid%5D.rb", uri.to_s)
    end

    def test_from_path_with_braces
      uri = URI::Generic.from_path(path: "/some/path/{slug}.rb")
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
      assert_equal("file:///some/path/%28id%29.rb", uri.to_s)
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
      assert_equal("file:///some/path/file%20%28copy%29.rb", uri.to_s)
    end

    # The editor and the server must escape paths identically, otherwise the same file is tracked under two different
    # URIs and the index ends up with duplicate entries (Shopify/ruby-lsp#3639). These expectations were captured from
    # the `vscode-uri` package, which is what VS Code uses to build the URIs it sends us
    def test_from_path_escapes_every_character_the_editor_escapes
      {
        "/some/path/[id].rb" => "file:///some/path/%5Bid%5D.rb",
        "/some/path/{slug}.rb" => "file:///some/path/%7Bslug%7D.rb",
        "/some/path/(id).rb" => "file:///some/path/%28id%29.rb",
        "/some/path/a&b.rb" => "file:///some/path/a%26b.rb",
        "/some/path/a,b.rb" => "file:///some/path/a%2Cb.rb",
        "/some/path/a+b.rb" => "file:///some/path/a%2Bb.rb",
        "/some/path/a=b.rb" => "file:///some/path/a%3Db.rb",
        "/some/path/a@b.rb" => "file:///some/path/a%40b.rb",
        "/some/path/a;b.rb" => "file:///some/path/a%3Bb.rb",
        "/some/path/a!b.rb" => "file:///some/path/a%21b.rb",
        "/some/path/a*b.rb" => "file:///some/path/a%2Ab.rb",
        "/some/path/a$b.rb" => "file:///some/path/a%24b.rb",
        "/some/path/it's.rb" => "file:///some/path/it%27s.rb",
        "/some/path/with space.rb" => "file:///some/path/with%20space.rb",
      }.each do |path, expected|
        uri = URI::Generic.from_path(path: path)
        assert_equal(expected, uri.to_s)
        assert_equal(path, uri.to_standardized_path)
      end
    end

    def test_from_path_does_not_escape_unreserved_characters
      path = "/some/path/a-b_c.d~e.rb"
      uri = URI::Generic.from_path(path: path)
      assert_equal("file:///some/path/a-b_c.d~e.rb", uri.to_s)
      assert_equal(path, uri.to_standardized_path)
    end

    def test_from_path_with_question_mark
      # A question mark used to be treated as safe, which made `URI::Generic.build` reject the escaped path for not
      # being a valid absolute path component
      uri = URI::Generic.from_path(path: "/some/path/what?.rb")
      assert_equal("file:///some/path/what%3F.rb", uri.to_s)
      assert_equal("/some/path/what?.rb", uri.to_standardized_path)
    end
  end
end
