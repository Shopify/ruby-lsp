# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class SemanticHighlightingExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::SemanticHighlighting, "semantic_highlighting"

  def run_expectations(source)
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: URI("file:///fake.rb"))
    range = @__params&.any? ? @__params.first : nil

    if range
      start_line = range.dig(:start, :line)
      end_line = range.dig(:end, :line)
      processed_range = start_line..end_line
    end

    dispatcher = Prism::Dispatcher.new
    global_state = RubyLsp::GlobalState.new
    global_state.apply_options({})
    listener = RubyLsp::Requests::SemanticHighlighting.new(
      global_state,
      dispatcher,
      document,
      nil,
      range: processed_range,
    )

    dispatcher.dispatch(document.parse_result.value)
    listener.perform
  end

  def assert_expectations(source, expected)
    actual = run_expectations(source).data
    assert_equal(json_expectations(expected).to_json, decode_tokens(actual).to_json)
  end

  def test_semantic_highlighting_addon
    source = <<~RUBY
      class Post
        custom_method :foo
        before_create :set_defaults
      end
    RUBY

    begin
      create_semantic_highlighting_addon

      with_server(source) do |server, uri|
        server.process_message({
          id: 1,
          method: "textDocument/semanticTokens/full",
          params: { textDocument: { uri: uri } },
        })

        result = server.pop_response
        assert_instance_of(RubyLsp::Result, result)

        decoded_response = decode_tokens(result.response.data)
        assert_equal(
          { delta_line: 0, delta_start_char: 6, length: 4, token_type: 2, token_modifiers: 1 },
          decoded_response[0],
        )
        assert_equal(
          { delta_line: 1, delta_start_char: 2, length: 13, token_type: 13, token_modifiers: 0 },
          decoded_response[1],
        )
        # This is the token modified by the addon
        assert_equal(
          { delta_line: 1, delta_start_char: 2, length: 13, token_type: 15, token_modifiers: 1 },
          decoded_response[2],
        )
      end
    ensure
      RubyLsp::Addon.addon_classes.clear
    end
  end

  private

  def create_semantic_highlighting_addon
    Class.new(RubyLsp::Addon) do
      def create_semantic_highlighting_listener(response_builder, dispatcher)
        klass = Class.new do
          include RubyLsp::Requests::Support::Common

          def initialize(response_builder, dispatcher)
            @response_builder = response_builder
            dispatcher.register(self, :on_call_node_enter)
          end

          def on_call_node_enter(node)
            current_token = @response_builder.last
            if node.message == "before_create" && @response_builder.last_token_matches?(node.message_loc)
              current_token.replace_type(:keyword)
              current_token.replace_modifier([:declaration])
            end
          end
        end

        T.unsafe(klass).new(response_builder, dispatcher)
      end

      def activate(global_state, outgoing_queue); end

      def deactivate; end

      def name; end

      def version
        "0.1.0"
      end
    end
  end

  def decode_tokens(array)
    tokens = []
    array.each_slice(5) do |token|
      tokens << {
        delta_line: token[0],
        delta_start_char: token[1],
        length: token[2],
        token_type: token[3],
        token_modifiers: token[4],
      }
    end
    tokens
  end
end
