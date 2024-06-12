# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class RBSIndexerTest < TestCase
    def test_index_core_classes
      entries = @index["Array"]
      refute_nil(entries)
      # Array is a class but also an instance method on Kernel
      assert_equal(2, entries.length)
      entry = entries.find { |entry| entry.is_a?(RubyIndexer::Entry::Class) }
      assert_match(%r{/gems/rbs-.*/core/array.rbs}, entry.file_path)
      assert_equal("array.rbs", entry.file_name)
      assert_equal("Object", entry.parent_class)
      assert_equal(1, entry.mixin_operations.length)
      enumerable_include = entry.mixin_operations.first
      assert_equal("Enumerable", enumerable_include.module_name)

      # Using fixed positions would be fragile, so let's just check some basics.
      assert_operator(entry.location.start_line, :>, 0)
      assert_operator(entry.location.end_line, :>, entry.location.start_line)
      assert_equal(0, entry.location.start_column)
      assert_operator(entry.location.end_column, :>, 0)
    end

    def test_index_core_modules
      entries = @index["Kernel"]
      refute_nil(entries)
      assert_equal(1, entries.length)
      entry = entries.first
      assert_match(%r{/gems/rbs-.*/core/kernel.rbs}, entry.file_path)
      assert_equal("kernel.rbs", entry.file_name)

      # Using fixed positions would be fragile, so let's just check some basics.
      assert_operator(entry.location.start_line, :>, 0)
      assert_operator(entry.location.end_line, :>, entry.location.start_line)
      assert_equal(0, entry.location.start_column)
      assert_operator(entry.location.end_column, :>, 0)
    end

    def test_index_methods
      entries = @index["initialize"]
      refute_nil(entries)
      entry = entries.find { |entry| entry.owner.name == "Array" }
      assert_match(%r{/gems/rbs-.*/core/array.rbs}, entry.file_path)
      assert_equal("array.rbs", entry.file_name)
      assert_equal(Entry::Visibility::PUBLIC, entry.visibility)

      # Using fixed positions would be fragile, so let's just check some basics.
      assert_operator(entry.location.start_line, :>, 0)
      assert_operator(entry.location.end_line, :>, entry.location.start_line)
      assert_equal(2, entry.location.start_column)
      assert_operator(entry.location.end_column, :>, 0)
    end
  end
end
