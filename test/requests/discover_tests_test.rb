# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class DiscoverTestsTest < Minitest::Test
    def test_minitest
      source = File.read("test/fixtures/minitest_tests.rb")

      with_minitest_test(source) do |items|
        assert_equal(["Test", "AnotherTest"], items.map { |i| i[:label] })
        assert_equal(
          [
            "test_public",
            "test_public_command",
            "test_another_public",
            "test_public_vcall",
            "test_with_q?",
          ],
          items[0][:children].map { |i| i[:label] },
        )
        assert_equal(["test_public", "test_public_2"], items[1][:children].map { |i| i[:label] })
        assert_all_items_tagged_with(items, :minitest)
      end
    end

    def test_minitest_with_nested_classes_and_modules
      source = File.read("test/fixtures/minitest_nested_classes_and_modules.rb")

      with_minitest_test(source) do |items|
        assert_equal(
          [
            "Foo::FooTest",
            "Foo::Bar::BarTest",
            "Foo::Bar::BarTest::Baz::BazTest",
            "Foo::Baz::BazTest",
            "Foo::Bar::FooBarTest",
            "Foo::Bar::FooBar::Test",
          ],
          items.map { |i| i[:label] },
        )

        assert_equal(["test_foo", "test_foo_2"], items[0][:children].map { |i| i[:label] })
        assert_equal(["test_bar"], items[1][:children].map { |i| i[:label] })
        assert_equal(["test_baz", "test_baz_2"], items[2][:children].map { |i| i[:label] })
        assert_equal(["test_baz"], items[3][:children].map { |i| i[:label] })
        assert_equal(["test_foo_bar", "test_foo_bar_2"], items[4][:children].map { |i| i[:label] })
        assert_equal(["test_foo_bar_baz"], items[5][:children].map { |i| i[:label] })
        assert_all_items_tagged_with(items, :minitest)
      end
    end

    def test_minitest_with_dynamic_constant_path
      source = File.read("test/fixtures/minitest_with_dynamic_constant_path.rb")

      with_minitest_test(source) do |items|
        assert_equal(
          [
            "<dynamic_reference>::Baz::Test",
            "<dynamic_reference>::Baz::Test::NestedTest",
            "<dynamic_reference>::Baz::SomeOtherTest",
          ],
          items.map { |i| i[:label] },
        )

        assert_equal(["test_something", "test_something_else"], items[0][:children].map { |i| i[:label] })
        assert_equal(["test_nested"], items[1][:children].map { |i| i[:label] })
        assert_equal(["test_stuff", "test_other_stuff"], items[2][:children].map { |i| i[:label] })
        assert_all_items_tagged_with(items, :minitest)
      end
    end

    def test_test_unit_cases
      source = <<~RUBY
        module Foo
          class MyTest < Test::Unit::TestCase
            def test_something; end

            private

            def test_should_not_be_included; end

            class NestedTest < Test::Unit::TestCase
              def test_hello; end
            end
          end
        end
      RUBY

      with_test_unit(source) do |items|
        assert_equal(["Foo::MyTest", "Foo::MyTest::NestedTest"], items.map { |i| i[:label] })

        assert_equal(["test_something"], items[0][:children].map { |i| i[:label] })
        assert_equal(["test_hello"], items[1][:children].map { |i| i[:label] })
        assert_all_items_tagged_with(items, :test_unit)
      end
    end

    def test_ignores_minitest_tests_that_extend_active_support_declarative
      source = <<~RUBY
        class MyTest < ActiveSupport::TestCase
          def test_something; end
        end
      RUBY

      with_active_support_declarative_tests(source) do |items|
        assert_empty(items)
      end
    end

    def test_dynamic_constant_in_minitest_tests
      source = <<~RUBY
        module var::Namespace
          class MyTest < Minitest::Test
            def test_something; end
            def do_something; end
          end
        end

        module Foo
          class var::OtherTest < Minitest::Test
            def test_something; end
          end
        end
      RUBY

      with_minitest_test(source) do |items|
        assert_equal(
          ["<dynamic_reference>::Namespace::MyTest", "Foo::<dynamic_reference>::OtherTest"],
          items.map { |i| i[:label] },
        )
        assert_equal(["test_something"], items[0][:children].map { |i| i[:label] })
        assert_equal(["test_something"], items[1][:children].map { |i| i[:label] })
        assert_all_items_tagged_with(items, :minitest)
      end
    end

    def test_dynamic_constant_in_test_unit_tests
      source = <<~RUBY
        module var::Namespace
          class MyTest < Test::Unit::TestCase
            def test_something; end

            def do_something; end
          end
        end

        module Foo
          class var::OtherTest < Test::Unit::TestCase
            def test_something; end
          end
        end
      RUBY

      with_minitest_test(source) do |items|
        assert_equal(
          ["<dynamic_reference>::Namespace::MyTest", "Foo::<dynamic_reference>::OtherTest"],
          items.map { |i| i[:label] },
        )
        assert_equal(["test_something"], items[0][:children].map { |i| i[:label] })
        assert_equal(["test_something"], items[1][:children].map { |i| i[:label] })
        assert_all_items_tagged_with(items, :test_unit)
      end
    end

    def test_files_are_indexed_lazily_if_needed
      path = File.join(Dir.pwd, "lib", "foo.rb")
      File.write(path, <<~RUBY)
        class FooTest < Test::Unit::TestCase
          def test_something; end
        end
      RUBY

      with_server do |server, uri|
        server.global_state.index.index_single(uri, <<~RUBY)
          module Test
            module Unit
              class TestCase; end
            end
          end
        RUBY

        server.process_message(
          id: 1,
          method: "rubyLsp/discoverTests",
          params: { textDocument: { uri: URI::Generic.from_path(path: path) } },
        )

        items = get_response(server)
        assert_equal(
          ["FooTest"],
          items.map { |i| i[:label] },
        )
        assert_equal(["test_something"], items[0][:children].map { |i| i[:label] })
        assert_all_items_tagged_with(items, :test_unit)
      end
    ensure
      FileUtils.rm(T.must(path))
    end

    def test_does_not_raise_on_duplicate_test_ids
      source = <<~RUBY
        module Foo
          class MyTest < Test::Unit::TestCase
            def test_something; end

            # This one gets picked
            def test_something; end
          end
        end
      RUBY

      with_test_unit(source) do |items|
        assert_equal(["Foo::MyTest"], items.map { |i| i[:label] })

        children = items[0][:children]
        assert_equal(1, children.length)

        test_something = children[0]
        assert_equal(5, test_something[:range].start.line)
        assert_all_items_tagged_with(items, :test_unit)
      end
    end

    def test_discovers_top_level_specs
      source = File.read("test/fixtures/minitest_spec_simple.rb")

      with_minitest_spec_configured(source) do |items|
        assert_equal(["BogusSpec"], items.map { |i| i[:label] })
        assert_all_items_tagged_with(items, :minitest)
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
          ["test one", "test two", "test three"],
          nested_specs.map { |i| i[:label] },
        )
        assert_all_items_tagged_with(items, :minitest)
      end
    end

    def test_discovers_specs_without_class
      source = File.read("test/fixtures/minitest_spec_tests.rb")

      with_minitest_spec_configured(source) do |items|
        top_level_specs = items
        assert_equal(
          ["Foo", "Foo::Bar", "Baz"],
          top_level_specs.map { |i| i[:label] },
        )

        nested_specs = top_level_specs[0][:children]
        assert_equal(
          ["it_level_one", "nested", "it_level_one_again"],
          nested_specs.map { |i| i[:label] },
        )
        assert_all_items_tagged_with(items, :minitest)
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
        assert_all_items_tagged_with(items, :minitest)
      end
    end

    def test_handles_empty_specs
      source = File.read("test/fixtures/minitest_spec_simple.rb")

      with_minitest_spec_configured(source) do |items|
        nested_specs = items[0][:children][0][:children]
        assert_empty(nested_specs)
        assert_all_items_tagged_with(items, :minitest)
      end
    end

    def test_handles_mixed_testing_styles_in_single_file
      source = <<~RUBY
        class FooSpec < Minitest::Spec
          it "does something" do
          end

          def test_also_valid; end
        end
      RUBY

      with_minitest_spec_configured(source) do |items|
        assert_equal(["FooSpec"], items.map { |i| i[:label] })
        assert_equal(
          [
            "does something",
            "test_also_valid",
          ],
          items[0][:children].map { |i| i[:label] },
        )
        assert_all_items_tagged_with(items, :minitest)
      end
    end

    def test_discover_tests_addons
      source = <<~RUBY
        class MyTest
          test "should do something" do
          end

          test "should do something else" do
          end
        end
      RUBY

      create_test_discovery_addon

      with_server(source) do |server, uri|
        server.process_message({
          id: 1,
          method: "rubyLsp/discoverTests",
          params: { textDocument: { uri: uri } },
        })

        response = pop_result(server)

        assert_instance_of(RubyLsp::Result, response)
        items = response.response

        test_classes = items.map { |i| i[:label] }
        assert_equal(["MyTest"], test_classes)

        test_methods = items[0][:children].map { |i| i[:label] }
        assert_equal(["should do something", "should do something else"], test_methods)
      end
    end

    private

    def create_test_discovery_addon
      Class.new(RubyLsp::Addon) do
        def create_discover_tests_listener(response_builder, dispatcher, uri)
          klass = Class.new do
            include RubyLsp::Requests::Support::Common

            def initialize(response_builder, dispatcher, uri)
              @response_builder = response_builder
              @uri = uri
              @current_class = nil
              dispatcher.register(self, :on_call_node_enter, :on_class_node_enter)
            end

            def on_class_node_enter(node)
              T.bind(self, RubyLsp::Requests::Support::Common)

              class_name = node.constant_path.slice

              if class_name == "MyTest"
                @current_class = RubyLsp::Requests::Support::TestItem.new(
                  class_name,
                  class_name,
                  @uri,
                  range_from_node(node),
                  framework: :custom_addon,
                )

                @response_builder.add(@current_class)
              end
            end

            def on_call_node_enter(node)
              T.bind(self, RubyLsp::Requests::Support::Common)

              arguments = node.arguments&.arguments
              first_arg = arguments&.first
              return unless first_arg.is_a?(Prism::StringNode)

              test_name = first_arg.content

              @current_class.add(RubyLsp::Requests::Support::TestItem.new(
                "#{@current_class.id}##{test_name}",
                test_name,
                @uri,
                range_from_node(node),
                framework: :custom_addon,
              ))
            end
          end

          klass.new(response_builder, dispatcher, uri)
        end

        def activate; end

        def deactivate; end

        def name; end

        def version
          "0.1.0"
        end
      end
    end

    def assert_all_items_tagged_with(items, tag)
      items.each do |item|
        assert_includes(item[:tags], "framework:#{tag}")
        children = item[:children]
        assert_all_items_tagged_with(children, tag) unless children.empty?
      end
    end

    def with_minitest_test(source, &block)
      with_server(source) do |server, uri|
        server.global_state.index.index_single(uri, <<~RUBY)
          module Minitest
            class Test; end
          end
        RUBY

        server.process_message(id: 1, method: "rubyLsp/discoverTests", params: {
          textDocument: { uri: uri },
        })

        items = get_response(server)

        yield items
      end
    end

    def with_test_unit(source, &block)
      with_server(source) do |server, uri|
        server.global_state.index.index_single(uri, <<~RUBY)
          module Test
            module Unit
              class TestCase; end
            end
          end
        RUBY

        server.process_message(id: 1, method: "rubyLsp/discoverTests", params: {
          textDocument: { uri: uri },
        })

        items = get_response(server)

        yield items
      end
    end

    def with_active_support_declarative_tests(source, &block)
      with_server(source) do |server, uri|
        server.global_state.index.index_single(uri, <<~RUBY)
          module Minitest
            class Test; end
          end

          module ActiveSupport
            module Testing
              module Declarative
              end
            end

            class TestCase < Minitest::Test
              extend Testing::Declarative
            end
          end
        RUBY

        server.process_message(id: 1, method: "rubyLsp/discoverTests", params: {
          textDocument: { uri: uri },
        })

        items = get_response(server)

        yield items
      end
    end

    def with_minitest_spec_configured(source, &block)
      with_server(source) do |server, uri|
        server.global_state.index.index_single(uri, <<~RUBY)
          module Minitest
            class Test; end
            class Spec < Test; end
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
