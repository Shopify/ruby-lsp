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
      end
    end

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
          ["test one", "test two", "test three"],
          nested_specs.map { |i| i[:label] },
        )
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
        assert_empty(nested_specs)
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
      end
    end

    private

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
