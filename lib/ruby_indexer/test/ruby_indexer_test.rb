# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyIndexer
  class RubyIndexerTest < Minitest::Test
    def test_load_configuration_executes_configure_block
      RubyIndexer.load_configuration_file
      files_to_index = RubyIndexer.configuration.files_to_index

      assert(files_to_index.none? { |path| path.include?("test/fixtures") })
      assert(files_to_index.none? { |path| path.include?("minitest-reporters") })
    end

    def test_paths_are_unique
      RubyIndexer.load_configuration_file
      files_to_index = RubyIndexer.configuration.files_to_index

      assert_equal(files_to_index.uniq.length, files_to_index.length)
    end

    def test_configuration_raises_for_unknown_keys
      assert_raises(ArgumentError) do
        RubyIndexer.configuration.apply_config({ "unknown" => 123 })
      end
    end
  end
end
