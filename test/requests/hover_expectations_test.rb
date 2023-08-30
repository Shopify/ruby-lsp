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
    index.index_single(uri.to_standardized_path, source)

    begin
      # We need to pretend that Sorbet is not a dependency or else we can't properly test
      RubyLsp::DependencyDetector.const_set(:HAS_TYPECHECKER, false)
      executor.execute({
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: position },
      }).response
    ensure
      RubyLsp::DependencyDetector.const_set(:HAS_TYPECHECKER, true)
      T.must(message_queue).close
    end
  end

  def test_hover_extensions
    RubyLsp::DependencyDetector.const_set(:HAS_TYPECHECKER, false)
    message_queue = Thread::Queue.new
    create_hover_extension

    store = RubyLsp::Store.new
    source = <<~RUBY
      # Hello
      class Post
      end

      Post
    RUBY
    uri = URI::Generic.from_path(path: "/fake.rb")
    store.set(uri: uri, source: source, version: 1)

    executor = RubyLsp::Executor.new(store, message_queue)
    executor.instance_variable_get(:@index).index_single(uri.to_standardized_path, source)

    response = executor.execute({
      method: "textDocument/hover",
      params: { textDocument: { uri: "file:///fake.rb" }, position: { line: 4, character: 0 } },
    }).response

    assert_match("Hello\n\nHello from middleware: Post", response.contents.value)
  ensure
    RubyLsp::Extension.extensions.clear
    RubyLsp::DependencyDetector.const_set(:HAS_TYPECHECKER, true)
    T.must(message_queue).close
  end

  private

  def create_hover_extension
    Class.new(RubyLsp::Extension) do
      def activate; end

      def name
        "HoverExtension"
      end

      def create_hover_listener(emitter, message_queue)
        klass = Class.new(RubyLsp::Listener) do
          attr_reader :response

          def initialize(emitter, message_queue)
            super
            emitter.register(self, :on_constant_read)
          end

          def on_constant_read(node)
            T.bind(self, RubyLsp::Listener[T.untyped])
            contents = RubyLsp::Interface::MarkupContent.new(
              kind: "markdown",
              value: "Hello from middleware: #{node.slice}",
            )
            @response = RubyLsp::Interface::Hover.new(range: range_from_location(node.location), contents: contents)
          end
        end

        klass.new(emitter, message_queue)
      end
    end
  end
end
