# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DocumentSymbolExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentSymbol, "document_symbol"

  def test_document_symbol_extensions
    RubyLsp::DependencyDetector.const_set(:HAS_TYPECHECKER, false)
    message_queue = Thread::Queue.new
    create_document_symbol_extension

    store = RubyLsp::Store.new
    source = <<~RUBY
      test "foo" do
      end
    RUBY
    uri = URI::Generic.from_path(path: "/fake.rb")
    store.set(uri: uri, source: source, version: 1)

    executor = RubyLsp::Executor.new(store, message_queue)
    executor.instance_variable_get(:@index).index_single(uri.to_standardized_path, source)

    response = executor.execute({
      method: "textDocument/documentSymbol",
      params: { textDocument: { uri: "file:///fake.rb" }, position: { line: 0, character: 1 } },
    }).response

    assert_equal("foo", response.first.name)
    assert_equal(LanguageServer::Protocol::Constant::SymbolKind::METHOD, response.first.kind)
  ensure
    RubyLsp::Extension.extensions.clear
    RubyLsp::DependencyDetector.const_set(:HAS_TYPECHECKER, true)
    T.must(message_queue).close
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
            emitter.register(self, :on_command)
          end

          def on_command(node)
            T.bind(self, RubyLsp::Listener[T.untyped])
            message_value = node.message.value
            return unless message_value == "test" && node.arguments.parts.any?

            first_argument = node.arguments.parts.first
            test_name = first_argument.parts.map(&:value).join

            @response = [RubyLsp::Interface::DocumentSymbol.new(
              name: test_name,
              kind: LanguageServer::Protocol::Constant::SymbolKind::METHOD,
              selection_range: range_from_syntax_tree_node(node),
              range: range_from_syntax_tree_node(node),
            )]
          end
        end

        klass.new(emitter, message_queue)
      end
    end
  end
end
