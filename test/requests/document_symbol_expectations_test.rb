# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DocumentSymbolExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentSymbol, "document_symbol"

  def test_labels_blank_names
    source = <<~RUBY
      def
    RUBY
    uri = URI("file:///fake.rb")

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::DocumentSymbol.new(dispatcher)
    dispatcher.dispatch(document.tree)
    response = listener.perform

    assert_equal(1, response.size)
    assert_equal("<blank>", T.must(response.first).name)
  end

  def test_document_symbol_addons
    source = <<~RUBY
      class Foo
        test "foo" do
        end
      end
    RUBY

    test_addon(:create_document_symbol_addon, source: source) do |server|
      server.process_message({
        id: 1,
        method: "textDocument/documentSymbol",
        params: { textDocument: { uri: "file:///fake.rb" } },
      })
      result = server.pop_response
      assert_instance_of(RubyLsp::Result, result)

      response = result.response

      assert_equal(1, response.count)
      assert_equal("Foo", response.first.name)

      test_symbol = response.first.children.first
      assert_equal(LanguageServer::Protocol::Constant::SymbolKind::METHOD, test_symbol.kind)
    end
  end

  def run_expectations(source)
    uri = URI("file://#{@_path}")
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::DocumentSymbol.new(uri, dispatcher)
    dispatcher.dispatch(document.tree)
    listener.perform
  end

  private

  def create_document_symbol_addon
    Class.new(RubyLsp::Addon) do
      def activate(message_queue); end

      def name
        "Document SymbolsAddon"
      end

      def deactivate; end

      def create_document_symbol_listener(response_builder, dispatcher)
        klass = Class.new do
          include RubyLsp::Requests::Support::Common

          def initialize(response_builder, dispatcher)
            @response_builder = response_builder
            dispatcher.register(self, :on_call_node_enter)
          end

          def on_call_node_enter(node)
            parent = @response_builder.last
            T.bind(self, RubyLsp::Requests::Support::Common)
            message_value = node.message
            arguments = node.arguments&.arguments
            return unless message_value == "test" && arguments&.any?

            parent.children << RubyLsp::Interface::DocumentSymbol.new(
              name: arguments.first.content,
              kind: LanguageServer::Protocol::Constant::SymbolKind::METHOD,
              selection_range: range_from_node(node),
              range: range_from_node(node),
            )
          end
        end

        T.unsafe(klass).new(response_builder, dispatcher)
      end
    end
  end
end
