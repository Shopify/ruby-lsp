# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class DiscoverSpecsTest < Minitest::Test
    def test_discovers_top_level_specs
      source = File.read("test/fixtures/minitest_spec_simple.rb")

      with_minitest_spec_configured(source) do |items|
        assert_equal(["BogusSpec"], items.map { |i| i[:label] })
      end
    end

    def test_discovers_nested_specs
      source = File.read("test/fixtures/minitest_spec_nested.rb")

      with_minitest_spec_configured(source) do |items|
        top_level_specs = items[0][:children]
        assert_equal(
          ["First Spec"],
          top_level_specs.map { |i| i[:label] },
        )

        nested_specs = top_level_specs[0][:children]
        assert_equal(
          ["test one", "test two"],
          nested_specs.map { |i| i[:label] },
        )
      end
    end

    def test_discovers_dynamic_spec_names
      source = File.read("test/fixtures/minitest_spec_dynamic_name.rb")

      with_minitest_spec_configured(source) do |items|
        nested_specs = items[0][:children][0][:children]
        assert_equal(
          ["dynamic_name"],
          nested_specs.map { |i| i[:label] },
        )
      end
    end

    def test_handles_empty_specs
      source = File.read("test/fixtures/minitest_spec_simple.rb")

      with_minitest_spec_configured(source) do |items|
        nested_specs = items[0][:children][0][:children]
        assert_empty(
          nested_specs.map { |i| i[:label] },
        )
      end
    end

    private

    def with_minitest_spec_configured(source, &block)
      with_server(source) do |server, uri|
        server.global_state.index.index_single(uri, <<~RUBY)
          module Minitest
            class Spec; end
          end
        RUBY

        server.process_message(id: 1, method: "rubyLsp/discoverTests", params: {
          textDocument: { uri: uri },
        })

        items = get_response(server)

        yield items
      end
    end

    def get_response(server)
      result = server.pop_response

      if result.is_a?(Error)
        flunk(result.message)
      end

      result.response
    end
  end
end
