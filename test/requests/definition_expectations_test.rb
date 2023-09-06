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
        nil,
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

    begin
      # We need to pretend that Sorbet is not a dependency or else we can't properly test
      RubyLsp::DependencyDetector.const_set(:HAS_TYPECHECKER, false)
      response = executor.execute({
        method: "textDocument/definition",
        params: { textDocument: { uri: "file:///folder/fake.rb" }, position: position },
      }).response
    ensure
      RubyLsp::DependencyDetector.const_set(:HAS_TYPECHECKER, true)
    end

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
    skip # restore the `ensure` when removing

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
    # ensure
    #   T.must(message_queue).close
  end
end
