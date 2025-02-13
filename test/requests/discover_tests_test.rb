# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class DiscoverTestsTest < Minitest::Test
    def test_minitest
      source = File.read("test/fixtures/minitest_tests.rb")

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

        assert_empty(get_response(server))
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

      with_server(source) do |server, uri|
        server.global_state.index.index_single(uri, <<~RUBY)
          module Minitest
            class Test; end
          end
        RUBY

        server.process_message(id: 1, method: "rubyLsp/discoverTests", params: { textDocument: { uri: uri } })

        items = get_response(server)
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

      with_server(source) do |server, uri|
        server.global_state.index.index_single(uri, <<~RUBY)
          module Test
            module Unit
              class TestCase; end
            end
          end
        RUBY

        server.process_message(id: 1, method: "rubyLsp/discoverTests", params: { textDocument: { uri: uri } })

        items = get_response(server)
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

    private

    def get_response(server)
      result = server.pop_response

      if result.is_a?(Error)
        flunk(result.message)
      end

      result.response
    end
  end
end
