# typed: true
# frozen_string_literal: true

# TODO: update all rubyapi.org links to https://ruby-doc.org/

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

    def test_rbs_method_with_required_positionals
      entries = @index["crypt"] # https://rubyapi.org/3.3/o/string#method-i-crypt
      assert_equal(1, entries.length)

      entry = entries.first
      parameters = entry.parameters

      assert_equal(1, parameters.length)
      assert_kind_of(Entry::RequiredParameter, parameters[0])
      assert_equal(:salt_str, parameters[0].name)
    end

    def test_rbs_method_with_optional_parameter
      entries = @index["chomp"] # https://rubyapi.org/3.3/o/string#method-i-chomp
      assert_equal(1, entries.length)

      entry = entries.first
      parameters = entry.parameters

      assert_equal(1, parameters.length)
      assert_kind_of(Entry::OptionalParameter, parameters[0])
      assert_equal(:separator, parameters[0].name)
    end

    def test_rbs_method_with_required_and_optional_parameters
      entries = @index["gsub"] # https://rubyapi.org/3.3/o/string#method-i-gsub
      assert_equal(1, entries.length)

      entry = entries.first

      parameters = entry.parameters
      # puts parameters.inspect

      assert_equal(3, parameters.length)
      assert_kind_of(Entry::RequiredParameter, parameters[0])
      assert_kind_of(Entry::OptionalParameter, parameters[1])
      assert_kind_of(Entry::BlockParameter, parameters[2])
      assert_equal(:pattern, parameters[0].name)
      assert_equal(:replacement, parameters[1].name)
      assert_equal(:match, parameters[2].name)
    end

    def test_rbs_anonymous_block_parameter
      # Overload 0
      # required_positionals: file_name
      # optional_positionals: mode, perm
      # rest_positional(s):
      # trailing_positionals:

      # Overload 1
      # required_positionals: file_name
      # optional_positionals: mode, perm
      # rest_positional(s):
      entries = @index["open"]
      entry = entries.find { |entry| entry.owner.name == "File::<Class:File>" }

      parameters = entry.parameters

      assert_equal([:file_name, :mode, :perm, :blk], parameters.map(&:name))
      assert_kind_of(Entry::RequiredParameter, parameters[0])
      assert_kind_of(Entry::OptionalParameter, parameters[1])
      assert_kind_of(Entry::OptionalParameter, parameters[2])
      assert_kind_of(Entry::BlockParameter, parameters[3])
      assert_equal(:file_name, parameters[0].name)
      assert_equal(:mode, parameters[1].name)
      assert_equal(:perm, parameters[2].name)
      assert_equal(:blk, parameters[3].name)
    end

    def test_rbs_method_with_rest_positionals
      entries = @index["count"] # https://rubyapi.org/3.3/o/string#method-i-count
      entry = entries.find { |entry| entry.owner.name == "String" }

      parameters = entry.parameters

      # TODO: In RBS, this is represented as having two arguments:
      #
      #   def count: (selector selector_0, *selector more_selectors) -> Integer
      #
      # but perhaps that is confusing?
      assert_equal([:selector_0, :more_selectors], parameters.map(&:name))
      assert_kind_of(RubyIndexer::Entry::RequiredParameter, parameters[0])
      assert_kind_of(RubyIndexer::Entry::RestParameter, parameters[1])
    end

    def test_rbs_method_with_trailing_positionals
      # Overload 0
      # required_positionals: read_array
      # optional_positionals: write_array, error_array
      # rest_positional(s):
      # trailing_positionals:

      # Overload 1
      # required_positionals: read_array
      # optional_positionals: write_array, error_array
      # rest_positional(s):
      # trailing_positionals: timeout
      entries = @index["select"] # https://ruby-doc.org/3.3.3/IO.html#method-c-select
      entry = entries.find { |entry| entry.owner.name == "IO::<Class:IO>" }

      parameters = entry.parameters

      assert_equal([:read_array, :write_array, :error_array, :timeout], parameters.map(&:name))
      assert_kind_of(Entry::RequiredParameter, parameters[0])
      assert_kind_of(Entry::OptionalParameter, parameters[1])
      assert_kind_of(Entry::OptionalParameter, parameters[2])
      assert_kind_of(Entry::OptionalParameter, parameters[3])
    end

    def test_rbs_method_with_optional_keywords
      entries = @index["step"] # https://rubyapi.org/3.3/o/numeric#method-i-step
      entry = entries.find { |entry| entry.owner.name == "Numeric" }

      parameters = entry.parameters

      assert_equal([:limit, :step, :blk, :by, :to], parameters.map(&:name)) # blk should be last?
      assert_kind_of(Entry::OptionalParameter, parameters[0])
      assert_kind_of(Entry::OptionalParameter, parameters[1])
      assert_kind_of(Entry::BlockParameter, parameters[2])
      assert_kind_of(Entry::OptionalKeywordParameter, parameters[3])
      assert_kind_of(Entry::OptionalKeywordParameter, parameters[4])
    end

    def test_rbs_method_with_required_keywords
      # Investigating if there are any methods in Core for this
    end

    def test_attaches_correct_owner_to_singleton_methods
      entries = @index["basename"]
      refute_nil(entries)

      owner = entries.first.owner
      assert_instance_of(Entry::SingletonClass, owner)
      assert_equal("File::<Class:File>", owner.name)
    end
  end
end
