# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DocumentSymbolExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentSymbol, "document_symbol"

  def test_document_symbol_addons
    source = <<~RUBY
      test "foo" do
      end
    RUBY

    test_addon(:create_document_symbol_addon, source: source) do |executor|
      response = executor.execute({
        method: "textDocument/documentSymbol",
        params: { textDocument: { uri: "file:///fake.rb" } },
      }).response

      assert_equal("foo", response.first.name)
      assert_equal(LanguageServer::Protocol::Constant::SymbolKind::METHOD, response.first.kind)
    end
  end

  private

  def create_document_symbol_addon
    Class.new(RubyLsp::Addon) do
      def activate; end

      def name
        "Document SymbolsAddon"
      end

      def create_document_symbol_listener(dispatcher, message_queue)
        klass = Class.new(RubyLsp::Listener) do
          attr_reader :_response

          def initialize(dispatcher, message_queue)
            super
            dispatcher.register(self, :on_call_node_enter)
          end

          def on_call_node_enter(node)
            T.bind(self, RubyLsp::Listener[T.untyped])
            message_value = node.message
            arguments = node.arguments&.arguments
            return unless message_value == "test" && arguments&.any?

            @_response = [RubyLsp::Interface::DocumentSymbol.new(
              name: arguments.first.content,
              kind: LanguageServer::Protocol::Constant::SymbolKind::METHOD,
              selection_range: range_from_node(node),
              range: range_from_node(node),
            )]
          end
        end

        klass.new(dispatcher, message_queue)
      end
    end
  end
end
