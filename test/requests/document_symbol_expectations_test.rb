# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class DocumentSymbolExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentSymbol, "document_symbol"

  def test_instance_variable_with_shorthand_assignment
    source = <<~RUBY
      @foo = 1
      @bar += 2
      @baz -= 3
      @qux ||= 4
      @quux &&= 5
    RUBY
    uri = URI("file:///fake.rb")

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::DocumentSymbol.new(uri, dispatcher)
    dispatcher.dispatch(document.ast)
    response = listener.perform

    assert_equal(5, response.size)

    assert_equal("@foo", response[0]&.name)
    assert_equal("@bar", response[1]&.name)
    assert_equal("@baz", response[2]&.name)
    assert_equal("@qux", response[3]&.name)
    assert_equal("@quux", response[4]&.name)
  end

  def test_instance_variable_with_destructuring_assignment
    source = <<~RUBY
      @a, @b = [1, 2]
      @c, @d, @e = [3, 4, 5]
    RUBY
    uri = URI("file:///fake.rb")

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::DocumentSymbol.new(uri, dispatcher)
    dispatcher.dispatch(document.ast)
    response = listener.perform

    assert_equal(5, response.size)

    assert_equal("@a", response[0]&.name)
    assert_equal("@b", response[1]&.name)
    assert_equal("@c", response[2]&.name)
    assert_equal("@d", response[3]&.name)
    assert_equal("@e", response[4]&.name)
  end

  def test_labels_blank_names
    source = <<~RUBY
      def
    RUBY
    uri = URI("file:///fake.rb")

    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::DocumentSymbol.new(uri, dispatcher)
    dispatcher.dispatch(document.ast)
    response = listener.perform

    assert_equal(1, response.size)
    assert_equal("<blank>", response.first&.name)
  end

  def test_document_symbol_addons
    source = <<~RUBY
      class Foo
        test "foo" do
        end
      end
    RUBY

    begin
      create_document_symbol_addon
      with_server(source) do |server, uri|
        server.process_message({
          id: 1,
          method: "textDocument/documentSymbol",
          params: { textDocument: { uri: uri } },
        })

        # Pop the re-indexing notification
        server.pop_response

        result = server.pop_response
        assert_instance_of(RubyLsp::Result, result)

        response = result.response

        assert_equal(1, response.count)
        assert_equal("Foo", response.first.name)

        test_symbol = response.first.children.first
        assert_equal(LanguageServer::Protocol::Constant::SymbolKind::METHOD, test_symbol.kind)
      end
    ensure
      RubyLsp::Addon.addon_classes.clear
    end
  end

  def run_expectations(source)
    uri = URI("file://#{@_path}")
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::DocumentSymbol.new(uri, dispatcher)
    dispatcher.dispatch(document.ast)
    listener.perform
  end

  private

  def create_document_symbol_addon
    Class.new(RubyLsp::Addon) do
      def activate(global_state, outgoing_queue); end

      def name
        "Document SymbolsAddon"
      end

      def deactivate; end

      def version
        "0.1.0"
      end

      def create_document_symbol_listener(response_builder, dispatcher)
        klass = Class.new do
          include RubyLsp::Requests::Support::Common

          def initialize(response_builder, dispatcher)
            @response_builder = response_builder
            dispatcher.register(self, :on_call_node_enter)
          end

          def on_call_node_enter(node)
            range = self #: as untyped # rubocop:disable Style/RedundantSelf
              .range_from_node(node)
            parent = @response_builder.last
            message_value = node.message
            arguments = node.arguments&.arguments
            return unless message_value == "test" && arguments&.any?

            parent.children << RubyLsp::Interface::DocumentSymbol.new(
              name: arguments.first.content,
              kind: LanguageServer::Protocol::Constant::SymbolKind::METHOD,
              selection_range: range,
              range: range,
            )
          end
        end

        klass.new(response_builder, dispatcher)
      end
    end
  end
end
