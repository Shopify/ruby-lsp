# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class TestCollectionTest < Minitest::Test
    def setup
      @uri = URI::Generic.from_path(path: "/fake_test.rb")
      @range = Interface::Range.new(
        start: Interface::Position.new(line: 0, character: 0),
        end: Interface::Position.new(line: 10, character: 3),
      )
    end

    def test_allows_building_hierarchy_of_tests
      builder = ResponseBuilders::TestCollection.new
      test_item = Requests::Support::TestItem.new("my-id", "Test label", @uri, @range, framework: :minitest)
      nested_item = Requests::Support::TestItem.new("nested-id", "Nested label", @uri, @range, framework: :minitest)

      builder.add(test_item)
      test_item.add(nested_item)

      item = builder["my-id"] #: as !nil
      assert(item)
      assert(item["nested-id"])

      builder.response.map(&:to_hash).each { |item| assert_expected_fields(item) }
    end

    def test_overrides_if_trying_to_add_item_with_same_id
      builder = ResponseBuilders::TestCollection.new
      test_item = Requests::Support::TestItem.new("my-id", "Test label", @uri, @range, framework: :minitest)
      nested_item = Requests::Support::TestItem.new("nested-id", "Nested label", @uri, @range, framework: :minitest)

      builder.add(test_item)
      test_item.add(nested_item)

      builder.add(Requests::Support::TestItem.new(
        "my-id",
        "Other title, but same ID",
        @uri,
        @range,
        framework: :minitest,
      ))
      assert_equal(
        "Other title, but same ID",
        builder["my-id"] #: as !nil
          .label,
      )

      test_item.add(Requests::Support::TestItem.new(
        "nested-id",
        "Other title, but same ID",
        @uri,
        @range,
        framework: :minitest,
      ))
      assert_equal(
        "Other title, but same ID",
        test_item["nested-id"] #: as !nil
          .label,
      )
    end

    private

    def assert_expected_fields(hash)
      [:id, :label, :uri, :range, :children, :tags].each do |field|
        assert(hash[field])
      end

      hash[:children].each { |child| assert_expected_fields(child) }
    end
  end
end
