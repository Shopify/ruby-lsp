# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DocumentSymbolExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentSymbol, "document_symbol"

  def test_document_symbol_extensions
    skip("Won't pass until other automatic requests are migrated")

    source = <<~RUBY
      test "foo" do
      end
    RUBY

    test_extension(:create_document_symbol_extension, source: source) do |executor|
      response = executor.execute({
        method: "textDocument/documentSymbol",
        params: { textDocument: { uri: "file:///fake.rb" } },
      }).response

      assert_equal("foo", response.first.name)
      assert_equal(LanguageServer::Protocol::Constant::SymbolKind::METHOD, response.first.kind)
    end
  end

  private

  def create_document_symbol_extension
    Class.new(RubyLsp::Extension) do
      def activate; end

      def name
        "Document SymbolsExtension"
      end

      def create_document_symbol_listener(emitter, message_queue)
        klass = Class.new(RubyLsp::Listener) do
          attr_reader :response

          def initialize(emitter, message_queue)
            super
            emitter.register(self, :on_call)
          end

          def on_call(node)
            T.bind(self, RubyLsp::Listener[T.untyped])
            message_value = node.message
            arguments = node.arguments&.arguments
            return unless message_value == "test" && arguments&.any?

            @response = [RubyLsp::Interface::DocumentSymbol.new(
              name: arguments.first.content,
              kind: LanguageServer::Protocol::Constant::SymbolKind::METHOD,
              selection_range: range_from_node(node),
              range: range_from_node(node),
            )]
          end
        end

        klass.new(emitter, message_queue)
      end
    end
  end
end
