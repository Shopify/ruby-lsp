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
    store.set(uri: "file:///folder/fake.rb", source: source, version: 1)

    response = RubyLsp::Executor.new(store, message_queue).execute({
      method: "textDocument/definition",
      params: { textDocument: { uri: "file:///folder/fake.rb" }, position: position },
    }).response

    if response
      attributes = response.attributes
      fake_path = attributes[:uri].split("/").last(2).join("/")
      response.instance_variable_set(:@attributes, attributes.merge("uri" => "file:///#{fake_path}"))
    end

    response
  ensure
    T.must(message_queue).close
  end
end
