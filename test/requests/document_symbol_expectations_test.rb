# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

module RubyLsp
  class DocumentSymbolExpectationsTest < ExpectationsTestRunner
    expectations_tests Requests::DocumentSymbol, "document_symbol"

    def test_document_symbol_extensions
      source = <<~RUBY
        test "foo" do
        end
      RUBY

      test_extension(:create_document_symbol_extension, source: source) do |executor|
        response = executor.execute({
          method: "textDocument/documentSymbol",
          params: { textDocument: { uri: "file:///fake.rb" }, position: { line: 0, character: 1 } },
        }).response

        assert_equal("foo", response.first.name)
        assert_equal(LanguageServer::Protocol::Constant::SymbolKind::METHOD, response.first.kind)
      end
    end

    private

    def create_document_symbol_extension
      Class.new(Extension) do
        def activate; end

        def name
          "Document SymbolsExtension"
        end

        def create_document_symbol_listener(emitter, message_queue)
          klass = Class.new(ExtensionListener) do
            attr_reader :_response

            def initialize(emitter, message_queue)
              super
              emitter.register(self, :on_command)
            end

            def on_command(node)
              T.bind(self, ExtensionListener[T.untyped])
              message_value = node.message.value
              return unless message_value == "test" && node.arguments.parts.any?

              first_argument = node.arguments.parts.first
              test_name = first_argument.parts.map(&:value).join

              @_response = [Interface::DocumentSymbol.new(
                name: test_name,
                kind: LanguageServer::Protocol::Constant::SymbolKind::METHOD,
                selection_range: range_from_syntax_tree_node(node),
                range: range_from_syntax_tree_node(node),
              )]
            end

            def merge_response(current_response)
              current_response.concat(@_response)
            end
          end

          klass.new(emitter, message_queue)
        end
      end
    end
  end
end
