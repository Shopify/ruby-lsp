# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DefinitionExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Definition, "definition"

  def run_expectations(source)
    message_queue = Thread::Queue.new
    position = @__params&.first || { character: 0, line: 0 }

    store = RubyLsp::Store.new
    store.set(uri: URI("file:///folder/fake.rb"), source: source, version: 1)
    executor = RubyLsp::Executor.new(store, message_queue)

    index = executor.instance_variable_get(:@index)
    index.index_single(
      RubyIndexer::IndexablePath.new(
        "#{Dir.pwd}/lib",
        File.expand_path(
          "../../test/fixtures/class_reference_target.rb",
          __dir__,
        ),
      ),
    )
    index.index_single(
      RubyIndexer::IndexablePath.new(
        nil,
        File.expand_path(
          "../../test/fixtures/constant_reference_target.rb",
          __dir__,
        ),
      ),
    )
    index.index_single(
      RubyIndexer::IndexablePath.new(
        "#{Dir.pwd}/lib",
        File.expand_path(
          "../../lib/ruby_lsp/executor.rb",
          __dir__,
        ),
      ),
    )

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    stub_no_typechecker
    response = executor.execute({
      method: "textDocument/definition",
      params: { textDocument: { uri: "file:///folder/fake.rb" }, position: position },
    }).response

    case response
    when RubyLsp::Interface::Location
      attributes = response.attributes
      fake_path = attributes[:uri].split("/").last(2).join("/")
      response.instance_variable_set(:@attributes, attributes.merge("uri" => "file:///#{fake_path}"))
    when Array
      response.each do |location|
        attributes = T.let(location.attributes, T.untyped)
        fake_path = T.let(attributes[:uri].split("/").last(2).join("/"), String)
        location.instance_variable_set(:@attributes, attributes.merge("uri" => "file:///#{fake_path}"))
      end
    end

    response
  ensure
    T.must(message_queue).close
  end

  def test_jumping_to_default_gems
    message_queue = Thread::Queue.new
    position = { character: 0, line: 0 }

    path = "#{RbConfig::CONFIG["rubylibdir"]}/pathname.rb"
    uri = URI::Generic.from_path(path: path)

    store = RubyLsp::Store.new
    store.set(uri: URI("file:///folder/fake.rb"), source: <<~RUBY, version: 1)
      Pathname
    RUBY

    executor = RubyLsp::Executor.new(store, message_queue)
    executor.instance_variable_get(:@index).index_single(
      RubyIndexer::IndexablePath.new(
        nil,
        T.must(uri.to_standardized_path),
      ),
    )

    response = executor.execute({
      method: "textDocument/definition",
      params: { textDocument: { uri: "file:///folder/fake.rb" }, position: position },
    }).response

    refute_empty(response)
  ensure
    T.must(message_queue).close
  end

  def test_jumping_to_default_require_of_a_gem
    message_queue = Thread::Queue.new

    store = RubyLsp::Store.new
    store.set(uri: URI("file:///folder/fake.rb"), source: <<~RUBY, version: 1)
      require "bundler"
    RUBY

    executor = RubyLsp::Executor.new(store, message_queue)

    uri = URI::Generic.from_path(path: "#{RbConfig::CONFIG["rubylibdir"]}/bundler.rb")
    executor.instance_variable_get(:@index).index_single(
      RubyIndexer::IndexablePath.new(RbConfig::CONFIG["rubylibdir"], T.must(uri.to_standardized_path)),
    )

    Dir.glob("#{RbConfig::CONFIG["rubylibdir"]}/bundler/*.rb").each do |path|
      executor.instance_variable_get(:@index).index_single(
        RubyIndexer::IndexablePath.new(RbConfig::CONFIG["rubylibdir"], path),
      )
    end

    response = executor.execute({
      method: "textDocument/definition",
      params: { textDocument: { uri: "file:///folder/fake.rb" }, position: { character: 10, line: 0 } },
    }).response

    assert_equal(uri.to_s, response.first.attributes[:uri])
  ensure
    T.must(message_queue).close
  end

  def test_jumping_to_private_constant_inside_the_same_namespace
    message_queue = Thread::Queue.new
    store = RubyLsp::Store.new

    uri = URI("file:///folder/fake.rb")
    source = <<~RUBY
      class A
        CONST = 123
        private_constant(:CONST)

        CONST
      end
    RUBY

    store.set(uri: uri, source: source, version: 1)

    executor = RubyLsp::Executor.new(store, message_queue)

    executor.instance_variable_get(:@index).index_single(
      RubyIndexer::IndexablePath.new(nil, T.must(uri.to_standardized_path)), source
    )

    stub_no_typechecker
    response = executor.execute({
      method: "textDocument/definition",
      params: { textDocument: { uri: "file:///folder/fake.rb" }, position: { character: 2, line: 4 } },
    })

    assert_nil(response.error, response.error&.full_message)
    assert_equal(uri.to_s, response.response.first.attributes[:uri])
  ensure
    T.must(message_queue).close
  end

  def test_jumping_to_private_constant_from_different_namespace
    message_queue = Thread::Queue.new
    store = RubyLsp::Store.new

    uri = URI("file:///folder/fake.rb")
    source = <<~RUBY
      class A
        CONST = 123
        private_constant(:CONST)
      end

      A::CONST # invalid private reference
    RUBY

    store.set(uri: uri, source: source, version: 1)

    executor = RubyLsp::Executor.new(store, message_queue)

    executor.instance_variable_get(:@index).index_single(
      RubyIndexer::IndexablePath.new(nil, T.must(uri.to_standardized_path)), source
    )

    stub_no_typechecker
    response = executor.execute({
      method: "textDocument/definition",
      params: { textDocument: { uri: "file:///folder/fake.rb" }, position: { character: 0, line: 5 } },
    }).response

    assert_empty(response)
  ensure
    T.must(message_queue).close
  end

  def test_definition_addons
    source = <<~RUBY
      RubyLsp
    RUBY

    test_addon(:create_definition_addon, source: source) do |executor|
      index = executor.instance_variable_get(:@index)
      index.index_single(
        RubyIndexer::IndexablePath.new(
          "#{Dir.pwd}/lib",
          File.expand_path(
            "../../test/fixtures/class_reference_target.rb",
            __dir__,
          ),
        ),
      )
      response = executor.execute({
        method: "textDocument/definition",
        params: { textDocument: { uri: "file:///fake.rb" }, position: { line: 0, character: 0 } },
      }).response

      assert_equal(2, response.size)
      assert_match("class_reference_target.rb", response[0].uri)
      assert_match("generated_by_addon.rb", response[1].uri)
    end
  end

  def test_jumping_to_method_definitions_when_declaration_exists
    message_queue = Thread::Queue.new
    store = RubyLsp::Store.new

    uri = URI("file:///folder/fake.rb")
    source = <<~RUBY
      # typed: false

      class A
        def bar
          foo
        end

        def foo; end
      end
    RUBY

    store.set(uri: uri, source: source, version: 1)

    executor = RubyLsp::Executor.new(store, message_queue)

    executor.instance_variable_get(:@index).index_single(
      RubyIndexer::IndexablePath.new(nil, T.must(uri.to_standardized_path)), source
    )

    response = executor.execute({
      method: "textDocument/definition",
      params: { textDocument: { uri: "file:///folder/fake.rb" }, position: { character: 4, line: 4 } },
    }).response

    assert_equal(uri.to_s, response.first.attributes[:uri])
  ensure
    T.must(message_queue).close
  end

  def test_can_jump_to_method_with_two_definitions
    message_queue = Thread::Queue.new
    store = RubyLsp::Store.new

    first_uri = URI("file:///folder/fake.rb")
    first_source = <<~RUBY
      # typed: false

      class A
        def bar
          foo
        end

        def foo; end
      end
    RUBY

    second_uri = URI("file:///folder/fake2.rb")
    second_source = <<~RUBY
      # typed: false

      class A
        def foo; end
      end
    RUBY

    store.set(uri: first_uri, source: first_source, version: 1)
    store.set(uri: second_uri, source: second_source, version: 1)

    executor = RubyLsp::Executor.new(store, message_queue)

    executor.instance_variable_get(:@index).index_single(
      RubyIndexer::IndexablePath.new(nil, T.must(first_uri.to_standardized_path)), first_source
    )
    executor.instance_variable_get(:@index).index_single(
      RubyIndexer::IndexablePath.new(nil, T.must(second_uri.to_standardized_path)), second_source
    )

    response = executor.execute({
      method: "textDocument/definition",
      params: { textDocument: { uri: "file:///folder/fake.rb" }, position: { character: 4, line: 4 } },
    }).response

    first_definition, second_definition = response
    assert_equal(first_uri.to_s, first_definition.attributes[:uri])
    assert_equal(second_uri.to_s, second_definition.attributes[:uri])
  ensure
    T.must(message_queue).close
  end

  def test_jumping_to_method_method_calls_on_explicit_self
    message_queue = Thread::Queue.new
    store = RubyLsp::Store.new

    uri = URI("file:///folder/fake.rb")
    source = <<~RUBY
      # typed: false

      class A
        def bar
          self.foo
        end

        def foo; end
      end
    RUBY

    store.set(uri: uri, source: source, version: 1)

    executor = RubyLsp::Executor.new(store, message_queue)

    executor.instance_variable_get(:@index).index_single(
      RubyIndexer::IndexablePath.new(nil, T.must(uri.to_standardized_path)), source
    )

    response = executor.execute({
      method: "textDocument/definition",
      params: { textDocument: { uri: "file:///folder/fake.rb" }, position: { character: 9, line: 4 } },
    }).response

    assert_equal(uri.to_s, response.first.attributes[:uri])
  ensure
    T.must(message_queue).close
  end

  def test_does_nothing_when_declaration_does_not_exist
    message_queue = Thread::Queue.new
    store = RubyLsp::Store.new

    uri = URI("file:///folder/fake.rb")
    source = <<~RUBY
      # typed: false

      class A
        def bar
          foo
        end
      end
    RUBY

    store.set(uri: uri, source: source, version: 1)

    executor = RubyLsp::Executor.new(store, message_queue)

    executor.instance_variable_get(:@index).index_single(
      RubyIndexer::IndexablePath.new(nil, T.must(uri.to_standardized_path)), source
    )

    response = executor.execute({
      method: "textDocument/definition",
      params: { textDocument: { uri: "file:///folder/fake.rb" }, position: { character: 4, line: 4 } },
    }).response

    assert_empty(response)
  ensure
    T.must(message_queue).close
  end

  private

  def create_definition_addon
    Class.new(RubyLsp::Addon) do
      def create_definition_listener(response_builder, uri, nesting, index, dispatcher)
        klass = Class.new do
          def initialize(response_builder, uri, _, _, dispatcher)
            @uri = uri
            @response_builder = response_builder
            dispatcher.register(self, :on_constant_read_node_enter)
          end

          def on_constant_read_node_enter(node)
            location = node.location
            @response_builder << RubyLsp::Interface::Location.new(
              uri: "file:///generated_by_addon.rb",
              range: RubyLsp::Interface::Range.new(
                start: RubyLsp::Interface::Position.new(
                  line: location.start_line - 1,
                  character: location.start_column,
                ),
                end: RubyLsp::Interface::Position.new(line: location.end_line - 1, character: location.end_column),
              ),
            )
          end
        end

        T.unsafe(klass).new(response_builder, uri, nesting, index, dispatcher)
      end

      def activate(message_queue); end

      def deactivate; end

      def name; end
    end
  end
end
