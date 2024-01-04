# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class HoverExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Hover, "hover"

  def run_expectations(source)
    message_queue = Thread::Queue.new
    position = @__params&.first || { character: 0, line: 0 }

    uri = URI("file:///fake.rb")
    store = RubyLsp::Store.new
    store.set(uri: uri, source: source, version: 1)

    executor = RubyLsp::Executor.new(store, message_queue)
    index = executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, T.must(uri.to_standardized_path)), source)

    begin
      # We need to pretend that Sorbet is not a dependency or else we can't properly test
      stub_no_typechecker
      executor.execute({
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: position },
      }).response
    ensure
      T.must(message_queue).close
    end
  end

  def test_hovering_over_private_constant_from_the_same_namespace
    message_queue = Thread::Queue.new
    store = RubyLsp::Store.new

    uri = URI("file:///fake.rb")
    source = <<~RUBY
      class A
        CONST = 123
        private_constant(:CONST)

        CONST
      end
    RUBY
    store.set(uri: uri, source: source, version: 1)

    executor = RubyLsp::Executor.new(store, message_queue)
    index = executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, T.must(uri.to_standardized_path)), source)

    stub_no_typechecker
    response = executor.execute({
      method: "textDocument/hover",
      params: { textDocument: { uri: uri }, position: { character: 2, line: 4 } },
    }).response

    assert_match("CONST", response.contents.value)
  ensure
    T.must(message_queue).close
  end

  def test_hovering_methods_invoked_on_implicit_self
    message_queue = Thread::Queue.new
    store = RubyLsp::Store.new

    uri = URI("file:///fake.rb")
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
    store.set(uri: uri, source: source, version: 1)

    executor = RubyLsp::Executor.new(store, message_queue)
    index = executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, T.must(uri.to_standardized_path)), source)

    response = executor.execute({
      method: "textDocument/hover",
      params: { textDocument: { uri: uri }, position: { character: 4, line: 7 } },
    }).response

    assert_match("Hello from `foo`", response.contents.value)
  ensure
    T.must(message_queue).close
  end

  def test_hovering_methods_invoked_on_explicit_self
    message_queue = Thread::Queue.new
    store = RubyLsp::Store.new

    uri = URI("file:///fake.rb")
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
    store.set(uri: uri, source: source, version: 1)

    executor = RubyLsp::Executor.new(store, message_queue)
    index = executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, T.must(uri.to_standardized_path)), source)

    response = executor.execute({
      method: "textDocument/hover",
      params: { textDocument: { uri: uri }, position: { character: 9, line: 7 } },
    }).response

    assert_match("Hello from `foo`", response.contents.value)
  ensure
    T.must(message_queue).close
  end

  def test_hovering_over_private_constant_from_different_namespace
    message_queue = Thread::Queue.new
    store = RubyLsp::Store.new

    uri = URI("file:///fake.rb")
    source = <<~RUBY
      class A
        CONST = 123
        private_constant(:CONST)
      end

      A::CONST # invalid private reference
    RUBY
    store.set(uri: uri, source: source, version: 1)

    executor = RubyLsp::Executor.new(store, message_queue)
    index = executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, T.must(uri.to_standardized_path)), source)

    stub_no_typechecker
    response = executor.execute({
      method: "textDocument/hover",
      params: { textDocument: { uri: uri }, position: { character: 0, line: 5 } },
    }).response

    assert_nil(response)
  ensure
    T.must(message_queue).close
  end

  def test_hovering_over_gemfile_dependency
    message_queue = Thread::Queue.new
    store = RubyLsp::Store.new

    uri = URI("file:///Gemfile")
    source = <<~RUBY
      gem 'bundler'
    RUBY
    store.set(uri: uri, source: source, version: 1)

    executor = RubyLsp::Executor.new(store, message_queue)
    index = executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, T.must(uri.to_standardized_path)), source)

    stub_no_typechecker
    response = executor.execute({
      method: "textDocument/hover",
      params: { textDocument: { uri: uri }, position: { character: 0, line: 0 } },
    }).response

    assert_includes(response.contents.value, "bundler")
    assert_includes(
      response.contents.value,
      "Bundler manages an application's dependencies through its entire life, " \
        "across many machines, systematically and repeatably",
    )
  ensure
    T.must(message_queue).close
  end

  def test_hover_addons
    source = <<~RUBY
      # Hello
      class Post
      end

      Post
    RUBY

    test_addon(:create_hover_addon, source: source) do |executor|
      response = executor.execute({
        method: "textDocument/hover",
        params: { textDocument: { uri: "file:///fake.rb" }, position: { line: 4, character: 0 } },
      }).response

      assert_match("Hello\n\nHello from middleware: Post", response.contents.value)
    end
  end

  private

  def create_hover_addon
    Class.new(RubyLsp::Addon) do
      def activate(message_queue); end

      def name
        "HoverAddon"
      end

      def create_hover_listener(nesting, index, dispatcher)
        klass = Class.new(RubyLsp::Listener) do
          attr_reader :_response

          def initialize(dispatcher)
            super
            dispatcher.register(self, :on_constant_read_node_enter)
          end

          def on_constant_read_node_enter(node)
            T.bind(self, RubyLsp::Listener[T.untyped])
            contents = RubyLsp::Interface::MarkupContent.new(
              kind: "markdown",
              value: "Hello from middleware: #{node.slice}",
            )
            @_response = RubyLsp::Interface::Hover.new(range: range_from_location(node.location), contents: contents)
          end
        end

        klass.new(dispatcher)
      end
    end
  end
end
