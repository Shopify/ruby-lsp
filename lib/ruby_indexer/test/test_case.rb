# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyIndexer
  class TestCase < Minitest::Test
    def setup
      @index = Index.new
      RBSIndexer.new(@index).index_ruby_core
      @default_indexed_entries = @index.instance_variable_get(:@entries).dup
    end

    private

    def index(source, uri: URI::Generic.from_path(path: "/fake/path/foo.rb"))
      @index.index_single(uri, source)
    end

    def assert_entry(expected_name, type, expected_location, visibility: nil)
      entries = @index[expected_name] #: as !nil
      refute_nil(entries, "Expected #{expected_name} to be indexed")
      refute_empty(entries, "Expected #{expected_name} to be indexed")

      entry = entries.first #: as !nil
      assert_instance_of(type, entry, "Expected #{expected_name} to be a #{type}")

      location = entry.location
      location_string =
        "#{entry.file_path}:#{location.start_line - 1}-#{location.start_column}" \
          ":#{location.end_line - 1}-#{location.end_column}"

      assert_equal(expected_location, location_string)

      assert_equal(visibility, entry.visibility) if visibility
    end

    def refute_entry(expected_name)
      entries = @index[expected_name]
      assert_nil(entries, "Expected #{expected_name} to not be indexed")
    end

    def assert_no_indexed_entries
      assert_equal(@default_indexed_entries, @index.instance_variable_get(:@entries))
    end

    def assert_no_entry(entry)
      refute(@index.indexed?(entry), "Expected '#{entry}' to not be indexed")
    end
  end
end
