# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyIndexer
  class TestCase < Minitest::Test
    def setup
      @index = Index.new
    end

    private

    def index(source)
      @index.index_single(IndexablePath.new(nil, "/fake/path/foo.rb"), source)
    end

    def assert_entry(expected_name, type, expected_location)
      entries = @index[expected_name]
      refute_empty(entries, "Expected #{expected_name} to be indexed")

      entry = entries.first
      assert_instance_of(type, entry, "Expected #{expected_name} to be a #{type}")

      location = entry.location
      location_string =
        "#{entry.file_path}:#{location.start_line - 1}-#{location.start_column}" \
          ":#{location.end_line - 1}-#{location.end_column}"

      assert_equal(expected_location, location_string)
    end

    def refute_entry(expected_name)
      entries = @index[expected_name]
      assert_nil(entries, "Expected #{expected_name} to not be indexed")
    end

    def assert_no_entries
      assert_empty(@index.instance_variable_get(:@entries), "Expected nothing to be indexed")
    end

    def assert_no_entry(entry)
      refute(@index.instance_variable_get(:@entries).key?(entry), "Expected '#{entry}' to not be indexed")
    end
  end
end
