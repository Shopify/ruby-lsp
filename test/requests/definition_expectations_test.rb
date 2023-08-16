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
    store.experimental_features = true
    store.set(uri: URI("file:///folder/fake.rb"), source: source, version: 1)
    executor = RubyLsp::Executor.new(store, message_queue)

    executor.instance_variable_get(:@index).index_single(File.expand_path(
      "../../lib/ruby_lsp/event_emitter.rb",
      __dir__,
    ))

    begin
      # We need to pretend that Sorbet is not a dependency or else we can't properly test
      RubyLsp::Requests::Definition.const_set(:HAS_TYPECHECKER, false)
      response = executor.execute({
        method: "textDocument/definition",
        params: { textDocument: { uri: "file:///folder/fake.rb" }, position: position },
      }).response
    ensure
      RubyLsp::Requests::Definition.const_set(:HAS_TYPECHECKER, true)
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
end
