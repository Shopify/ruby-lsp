# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class CodeLensExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::CodeLens, "code_lens"

  def test_after_request_hook
    message_queue = Thread::Queue.new
    create_code_lens_hook_class

    store = RubyLsp::Store.new
    store.set(uri: "file:///fake.rb", source: <<~RUBY, version: 1)
      class Test < Minitest::Test; end
    RUBY

    response = RubyLsp::Executor.new(store, message_queue).execute({
      method: "textDocument/codeLens",
      params: { textDocument: { uri: "file:///fake.rb" }, position: { line: 1, character: 2 } },
    }).response

    assert_equal(response.size, 4)
    assert_match("Run", response[0].command.title)
    assert_match("Debug", response[1].command.title)
    assert_match("Run In Terminal", response[2].command.title)
    assert_match("Run Test", response[3].command.title)
  ensure
    RubyLsp::Requests::Hover.listeners.clear
    T.must(message_queue).close
  end

  private

  def create_code_lens_hook_class
    Class.new(RubyLsp::Listener) do
      attr_reader :response

      RubyLsp::Requests::CodeLens.add_listener(self)

      listener_events do
        def on_class(node)
          T.bind(self, RubyLsp::Listener[T.untyped])

          @response = [RubyLsp::Interface::CodeLens.new(
            range: range_from_syntax_tree_node(node),
            command: RubyLsp::Interface::Command.new(
              title: "Run #{node.constant.constant.value}",
              command: "rubyLsp.runTest",
            ),
          )]
        end
      end
    end
  end
end
