# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class RBSIndexerTest < TestCase
    def setup
      @index = RubyIndexer::Index.new
      RBSIndexer.new(@index).index_core_classes
    end

    def test_index_core_classes
      entries = @index["Array"]
      refute_nil(entries)
      assert_equal(1, entries.length)
      entry = entries.first
      assert_match(%r{/gems/rbs-.*/core/array.rbs}, entry.file_path)
      assert_equal("array.rbs", entry.file_name)
      assert_equal("Object", entry.parent_class)

      # Using fixed positions would be fragile, so let's just check some basics.
      assert_operator(entry.location.start_line, :>, 0)
      assert_operator(entry.location.end_line, :>, entry.location.start_line)
      assert_equal(0, entry.location.start_column)
      assert_operator(entry.location.end_column, :>, 0)
    end
  end
end
