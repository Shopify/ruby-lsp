# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DocumentSymbolExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentSymbol, "document_symbol"

  def test_document_symbol_addons
    source = <<~RUBY
      class Foo
        test "foo" do
        end
      end
    RUBY

    test_addon(:create_document_symbol_addon, source: source) do |executor|
      response = executor.execute({
        method: "textDocument/documentSymbol",
        params: { textDocument: { uri: "file:///fake.rb" } },
      })

      assert_nil(response.error, response.error&.full_message)

      response = response.response

      assert_equal(1, response.count)
      assert_equal("Foo", response.first.name)

      test_symbol = response.first.children.first
      assert_equal(LanguageServer::Protocol::Constant::SymbolKind::METHOD, test_symbol.kind)
    end
  end

  private

  def create_document_symbol_addon
    Class.new(RubyLsp::Addon) do
      def activate(message_queue); end

      def name
        "Document SymbolsAddon"
      end

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
