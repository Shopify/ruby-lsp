# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class HoverExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Hover, "hover"

  def run_expectations(source)
    position = @__params&.first || { character: 0, line: 0 }

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # We need to pretend that Sorbet is not a dependency or else we can't properly test
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: position },
      )
      server.pop_response.response
    end
  end

  def test_hovering_over_private_constant_from_the_same_namespace
    source = <<~RUBY
      class A
        CONST = 123
        private_constant(:CONST)

        CONST
      end
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 2, line: 4 } },
      )

      assert_match("CONST", server.pop_response.response.contents.value)
    end
  end

  def test_hovering_precision
    source = <<~RUBY
      module Foo
        module Bar
          class Baz
          end
        end
      end

      Foo::Bar::Baz
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # Foo
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 0 } },
      )
      assert_match(/Foo\b/, server.pop_response.response.contents.value)

      # Foo::Bar
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 5 } },
      )
      assert_match(/Foo::Bar\b/, server.pop_response.response.contents.value)

      # Foo::Bar::Baz
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 10 } },
      )
      assert_match(/Foo::Bar::Baz\b/, server.pop_response.response.contents.value)
    end
  end

  def test_hovering_methods_invoked_on_implicit_self
    source = <<~RUBY
      # typed: false

      class A
        # Hello from `foo`
        def foo; end

        def bar
          foo
        end
      end
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 7 } },
      )

      assert_match("Hello from `foo`", server.pop_response.response.contents.value)
    end
  end

  def test_hovering_methods_with_two_definitions
    source = <<~RUBY
      # typed: false

      class A
        # Hello from first `foo`
        def foo; end

        def bar
          foo
        end
      end

      class A
        # Hello from second `foo`
        def foo; end
      end
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 7 } },
      )

      response = server.pop_response.response
      assert_match("Hello from first `foo`", response.contents.value)
      assert_match("Hello from second `foo`", response.contents.value)
    end
  end

  def test_hovering_methods_invoked_on_explicit_self
    source = <<~RUBY
      # typed: false

      class A
        # Hello from `foo`
        def foo; end

        def bar
          self.foo
        end
      end
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 9, line: 7 } },
      )

      assert_match("Hello from `foo`", server.pop_response.response.contents.value)
    end
  end

  def test_hovering_over_private_constant_from_different_namespace
    source = <<~RUBY
      class A
        CONST = 123
        private_constant(:CONST)
      end

      A::CONST # invalid private reference
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 3, line: 5 } },
      )

      assert_nil(server.pop_response.response)
    end
  end

  def test_hovering_over_gemfile_dependency
    source = <<~RUBY
      gem 'rake'
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, URI("file:///Gemfile"), stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 0 } },
      )

      response = server.pop_response.response
      spec = Gem.loaded_specs["rake"]

      assert_includes(response.contents.value, spec.name)
      assert_includes(response.contents.value, spec.version.to_s)
      assert_includes(response.contents.value, spec.homepage)
    end
  end

  def test_hovering_over_gemfile_dependency_with_missing_argument
    source = <<~RUBY
      gem()
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, URI("file:///Gemfile"), stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 0 } },
      )

      assert_nil(server.pop_response.response)
    end
  end

  def test_hovering_over_gemfile_dependency_with_non_gem_argument
    source = <<~RUBY
      gem(method_call)
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, URI("file:///Gemfile"), stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 0 } },
      )

      assert_nil(server.pop_response.response)
    end
  end

  def test_hover_addons
    source = <<~RUBY
      # Hello
      class Post
      end

      Post
    RUBY

    begin
      create_hover_addon

      with_server(source) do |server, uri|
        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { character: 0, line: 4 } },
        )

        assert_match(<<~RESPONSE.strip, server.pop_response.response.contents.value)
          Title

          **Definitions**: [fake.rb](file:///fake.rb#L2,1-3,4)
          Links



          Hello
          Documentation from middleware: Post
        RESPONSE
      end
    ensure
      RubyLsp::Addon.addon_classes.clear
    end
  end

  def test_hover_precision_for_methods_with_block_arguments
    source = <<~RUBY
      class Foo
        # Hello
        def foo(&block); end

        def bar
          foo(&:argument)
        end
      end
    RUBY

    # Going to definition on `argument` should not take you to the `foo` method definition
    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 12, line: 5 } },
      )
      assert_nil(server.pop_response.response)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 5 } },
      )
      assert_match("Hello", server.pop_response.response.contents.value)
    end
  end

  def test_hover_instance_variables
    source = <<~RUBY
      class Foo
        def initialize
          # Hello
          @a = 1
        end

        def bar
          @a
        end

        def baz
          @a = 5
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 7 } },
      )
      assert_match("Hello", server.pop_response.response.contents.value)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 11 } },
      )
      assert_match("Hello", server.pop_response.response.contents.value)
    end
  end

  def test_hovering_over_inherited_methods
    source = <<~RUBY
      module Foo
        module First
          # Method 1
          def method1; end
        end

        class Bar
          # Method 2
          def method2; end
        end

        class Baz < Bar
          include First

          def method3
            method1
            method2
          end
        end
      end
    RUBY

    # Going to definition on `argument` should not take you to the `foo` method definition
    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 6, line: 15 } },
      )
      assert_match("Method 1", server.pop_response.response.contents.value)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 6, line: 16 } },
      )
      assert_match("Method 2", server.pop_response.response.contents.value)
    end
  end

  def test_hover_for_inherited_instance_variables
    source = <<~RUBY
      module Foo
        def set_ivar
          # Foo
          @a = 1
        end
      end

      class Parent
        def initialize
          # Parent
          @a = 5
        end
      end

      class Child < Parent
        include Foo

        def do_something
          @a
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 18 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Foo", contents)
      assert_match("Parent", contents)
    end
  end

  def test_hover_for_methods_shows_parameters
    source = <<~RUBY
      class Foo
        def bar(a, b = 1, *c, d:, e: 1, **f, &g)
        end

        def baz
          bar
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 5 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("bar(a, b = <default>, *c, d:, e: <default>, **f, &g)", contents)
    end
  end

  private

  def create_hover_addon
    Class.new(RubyLsp::Addon) do
      def activate(global_state, outgoing_queue); end

      def name
        "HoverAddon"
      end

      def deactivate; end

      def create_hover_listener(response_builder, nesting, dispatcher)
        klass = Class.new do
          def initialize(response_builder, dispatcher)
            @response_builder = response_builder
            dispatcher.register(self, :on_constant_read_node_enter)
          end

          def on_constant_read_node_enter(node)
            @response_builder.push(
              "Documentation from middleware: #{node.slice}", category: :documentation
            )
            @response_builder.push(
              "Links", category: :links
            )
            @response_builder.push(
              "Title", category: :title
            )
          end
        end

        klass.new(response_builder, dispatcher)
      end
    end
  end
end
