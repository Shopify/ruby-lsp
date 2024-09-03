# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class InlayHintsExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::InlayHints, "inlay_hints"

  def run_expectations(source)
    params = @__params&.any? ? @__params : default_args
    uri = URI("file://#{@_path}")
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri)

    dispatcher = Prism::Dispatcher.new
    hints_configuration = RubyLsp::RequestConfig.new({ implicitRescue: true, implicitHashValue: true })
    request = RubyLsp::Requests::InlayHints.new(document, params.first, hints_configuration, dispatcher)
    dispatcher.dispatch(document.parse_result.value)
    request.perform
  end

  def default_args
    [{ start: { line: 0, character: 0 }, end: { line: 20, character: 20 } }]
  end

  def test_skip_implicit_hash_value
    uri = URI("file://foo.rb")
    document = RubyLsp::RubyDocument.new(uri: uri, source: <<~RUBY, version: 1)
      {bar:, baz:}
    RUBY

    dispatcher = Prism::Dispatcher.new
    hints_configuration = RubyLsp::RequestConfig.new({ implicitRescue: true, implicitHashValue: false })
    request = RubyLsp::Requests::InlayHints.new(document, default_args.first, hints_configuration, dispatcher)
    dispatcher.dispatch(document.parse_result.value)
    request.perform
  end

  def test_skip_implicit_rescue
    uri = URI("file://foo.rb")
    document = RubyLsp::RubyDocument.new(uri: uri, source: <<~RUBY, version: 1)
      begin
      rescue
      end
    RUBY

    dispatcher = Prism::Dispatcher.new
    hints_configuration = RubyLsp::RequestConfig.new({ implicitRescue: false, implicitHashValue: true })
    request = RubyLsp::Requests::InlayHints.new(document, default_args.first, hints_configuration, dispatcher)
    dispatcher.dispatch(document.parse_result.value)
    assert_empty(request.perform)
  end

  def test_inlay_hint_addons
    source = <<~RUBY
      Foo
    RUBY

    begin
      create_inlay_hint_addon

      with_server(source) do |server, uri|
        server.process_message(
          id: 1,
          method: "textDocument/inlayHint",
          params: {
            textDocument: {
              uri: uri,
            },
            range: {
              start: { line: 0, character: 0 },
            },
          },
        )

        response = server.pop_response.response

        assert_equal(1, response.size)
        assert_match("MyInlayHint", response[0].label)
      end
    end
  end

  private

  def create_inlay_hint_addon
    Class.new(RubyLsp::Addon) do
      def activate(global_state, outgoing_queue); end

      def name
        "InlayHintAddon"
      end

      def deactivate; end

      def create_inlay_hint_listener(response_builder, dispatcher, document, range)
        klass = Class.new do
          def initialize(response_builder, dispatcher)
            @response_builder = response_builder
            dispatcher.register(self, :on_constant_read_node_enter)

            def on_constant_read_node_enter(node)
              @response_builder << RubyLsp::Interface::InlayHint.new(
                position: { line: node.location.start_line - 1, character: node.location.end_column },
                label: "MyInlayHint",
              )
            end
          end
        end

        T.unsafe(klass).new(response_builder, dispatcher)
      end
    end
  end
end
