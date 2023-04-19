# typed: true
# frozen_string_literal: true

require "test_helper"
require "net/http" # for stubbing
require "expectations/expectations_test_runner"

class HoverExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Hover, "hover"

  def assert_expectations(source, expected)
    source = substitute(source)
    actual = T.cast(run_expectations(source), T.nilable(LanguageServer::Protocol::Interface::Hover))
    actual_json = actual ? JSON.parse(actual.to_json) : nil
    assert_equal(json_expectations(substitute(expected)), actual_json)
  end

  def test_search_index_being_nil
    message_queue = Thread::Queue.new
    store = RubyLsp::Store.new
    store.set(uri: "file:///fake.rb", source: "belongs_to :foo", version: 1)

    RubyLsp::Requests::Support::RailsDocumentClient.stubs(search_index: nil)
    RubyLsp::Executor.new(store, message_queue).execute({
      method: "textDocument/hover",
      params: { textDocument: { uri: "file:///fake.rb" }, position: { line: 0, character: 0 } },
    }).response
  ensure
    T.must(message_queue).close
  end

  class FakeHTTPResponse
    attr_reader :code, :body

    def initialize(code, body)
      @code = code
      @body = body
    end
  end

  def run_expectations(source)
    message_queue = Thread::Queue.new
    js_content = File.read(File.join(TEST_FIXTURES_DIR, "rails_search_index.js"))
    fake_response = FakeHTTPResponse.new("200", js_content)

    position = @__params&.first || { character: 0, line: 0 }

    Net::HTTP.stubs(get_response: fake_response)
    store = RubyLsp::Store.new
    store.set(uri: "file:///fake.rb", source: source, version: 1)

    RubyLsp::Executor.new(store, message_queue).execute({
      method: "textDocument/hover",
      params: { textDocument: { uri: "file:///fake.rb" }, position: position },
    }).response
  ensure
    T.must(message_queue).close
  end

  def test_after_request_hook
    message_queue = Thread::Queue.new
    create_hover_hook_class
    js_content = File.read(File.join(TEST_FIXTURES_DIR, "rails_search_index.js"))
    fake_response = FakeHTTPResponse.new("200", js_content)
    Net::HTTP.stubs(get_response: fake_response)

    store = RubyLsp::Store.new
    store.set(uri: "file:///fake.rb", source: <<~RUBY, version: 1)
      class Post
        belongs_to :user
      end
    RUBY

    response = RubyLsp::Executor.new(store, message_queue).execute({
      method: "textDocument/hover",
      params: { textDocument: { uri: "file:///fake.rb" }, position: { line: 1, character: 2 } },
    }).response

    assert_match("Method from middleware: belongs_to", response.contents.value)
    assert_match("[Rails Document: `ActiveRecord::Associations::ClassMethods#belongs_to`]", response.contents.value)
  ensure
    RubyLsp::Requests::Hover.listeners.clear
    T.must(message_queue).close
  end

  private

  def create_hover_hook_class
    Class.new(RubyLsp::Listener) do
      attr_reader :response

      RubyLsp::Requests::Hover.add_listener(self)

      listener_events do
        def on_command(node)
          T.bind(self, RubyLsp::Listener[T.untyped])
          contents = RubyLsp::Interface::MarkupContent.new(
            kind: "markdown",
            value: "Method from middleware: #{node.message.value}",
          )
          @response = RubyLsp::Interface::Hover.new(range: range_from_syntax_tree_node(node), contents: contents)
        end
      end
    end
  end

  def substitute(original)
    original.gsub("RAILTIES_VERSION", Gem::Specification.find_by_name("railties").version.to_s)
  end
end
