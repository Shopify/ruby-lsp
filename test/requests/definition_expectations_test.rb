# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DefinitionExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Definition, "definition"

  def run_expectations(source)
    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, stub_no_typechecker: true) do |server, uri|
      position = @__params&.first || { character: 0, line: 0 }

      index = server.global_state.index

      index.index_single(
        RubyIndexer::IndexablePath.new(
          "#{Dir.pwd}/lib",
          File.expand_path(
            "../../test/fixtures/class_reference_target.rb",
            __dir__,
          ),
        ),
      )
      index.index_single(
        RubyIndexer::IndexablePath.new(
          nil,
          File.expand_path(
            "../../test/fixtures/constant_reference_target.rb",
            __dir__,
          ),
        ),
      )
      index.index_single(
        RubyIndexer::IndexablePath.new(
          "#{Dir.pwd}/lib",
          File.expand_path(
            "../../lib/ruby_lsp/server.rb",
            __dir__,
          ),
        ),
      )

      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: position },
      )
      response = server.pop_response.response

      case response
      when RubyLsp::Interface::Location
        attributes = response.attributes
        fake_path = attributes[:uri].split("/").last(2).join("/")
        response.instance_variable_set(:@attributes, attributes.merge("uri" => "file:///#{fake_path}"))
      when Array
        response.each do |location|
          attributes = T.let(location.attributes, T.untyped)
          fake_path = T.let(attributes[:uri].split("/").last(2).join("/"), String)
          location.instance_variable_set(:@attributes, attributes.merge("uri" => "file:///#{fake_path}"))
        end
      end

      response
    end
  end

  def test_jumping_to_default_gems
    with_server("Pathname") do |server, uri|
      index = server.global_state.index
      index.index_single(
        RubyIndexer::IndexablePath.new(
          nil,
          "#{RbConfig::CONFIG["rubylibdir"]}/pathname.rb",
        ),
      )
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 0 } },
      )
      refute_empty(server.pop_response.response)
    end
  end

  def test_constant_precision
    source = <<~RUBY
      module Foo
        module Bar
          class Baz
          end
        end
      end

      Foo::Bar::Baz
    RUBY

    with_server(source) do |server, uri|
      # Foo
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 0 } },
      )
      range = server.pop_response.response[0].attributes[:range].attributes
      range_hash = { start: range[:start].to_hash, end: range[:end].to_hash }
      assert_equal({ start: { line: 0, character: 0 }, end: { line: 5, character: 3 } }, range_hash)

      # Foo::Bar
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 5 } },
      )
      range = server.pop_response.response[0].attributes[:range].attributes
      range_hash = { start: range[:start].to_hash, end: range[:end].to_hash }
      assert_equal({ start: { line: 1, character: 2 }, end: { line: 4, character: 5 } }, range_hash)

      # Foo::Bar::Baz
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 10 } },
      )
      range = server.pop_response.response[0].attributes[:range].attributes
      range_hash = { start: range[:start].to_hash, end: range[:end].to_hash }
      assert_equal({ start: { line: 2, character: 4 }, end: { line: 3, character: 7 } }, range_hash)
    end
  end

  def test_jumping_to_default_require_of_a_gem
    with_server("require \"bundler\"") do |server, uri|
      index = server.global_state.index

      bundler_uri = URI::Generic.from_path(path: "#{RbConfig::CONFIG["rubylibdir"]}/bundler.rb")
      index.index_single(
        RubyIndexer::IndexablePath.new(RbConfig::CONFIG["rubylibdir"], T.must(bundler_uri.to_standardized_path)),
      )

      Dir.glob("#{RbConfig::CONFIG["rubylibdir"]}/bundler/*.rb").each do |path|
        index.index_single(
          RubyIndexer::IndexablePath.new(RbConfig::CONFIG["rubylibdir"], path),
        )
      end

      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 10, line: 0 } },
      )
      assert_equal(bundler_uri.to_s, server.pop_response.response.first.attributes[:uri])
    end
  end

  def test_jumping_to_private_constant_inside_the_same_namespace
    source = <<~RUBY
      class A
        CONST = 123
        private_constant(:CONST)

        CONST
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 2, line: 4 } },
      )
      response = server.pop_response

      assert_instance_of(RubyLsp::Result, response)
      assert_equal(uri.to_s, response.response.first.attributes[:uri])
    end
  end

  def test_jumping_to_private_constant_from_different_namespace
    source = <<~RUBY
      class A
        CONST = 123
        private_constant(:CONST)
      end

      A::CONST # invalid private reference
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 3, line: 5 } },
      )
      assert_empty(server.pop_response.response)
    end
  end

  def test_definition_addons
    source = <<~RUBY
      RubyLsp
    RUBY

    create_definition_addon

    with_server(source) do |server, uri|
      server.global_state.index.index_single(
        RubyIndexer::IndexablePath.new(
          "#{Dir.pwd}/lib",
          File.expand_path(
            "../../test/fixtures/class_reference_target.rb",
            __dir__,
          ),
        ),
      )
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 0 } },
      )
      response = server.pop_response.response

      assert_equal(2, response.size)
      assert_match("class_reference_target.rb", response[0].uri)
      assert_match("generated_by_addon.rb", response[1].uri)
    end
  end

  def test_jumping_to_method_definitions_when_declaration_exists
    source = <<~RUBY
      # typed: false

      class A
        def bar
          foo
        end

        def foo; end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 4 } },
      )
      assert_equal(uri.to_s, server.pop_response.response.first.attributes[:uri])
    end
  end

  def test_can_jump_to_method_with_two_definitions
    first_source = <<~RUBY
      # typed: false

      class A
        def bar
          foo
        end

        def foo; end
      end
    RUBY

    with_server(first_source) do |server, uri|
      second_uri = URI("file:///folder/fake2.rb")
      second_source = <<~RUBY
        # typed: false

        class A
          def foo; end
        end
      RUBY
      server.process_message({
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: second_uri,
            text: second_source,
            version: 1,
          },
        },
      })
      index = server.global_state.index
      index.index_single(RubyIndexer::IndexablePath.new(nil, T.must(second_uri.to_standardized_path)), second_source)

      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 4 } },
      )

      first_definition, second_definition = server.pop_response.response
      assert_equal(uri.to_s, first_definition.attributes[:uri])
      assert_equal(second_uri.to_s, second_definition.attributes[:uri])
    end
  end

  def test_jumping_to_method_method_calls_on_explicit_self
    source = <<~RUBY
      # typed: false

      class A
        def bar
          self.foo
        end

        def foo; end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 9, line: 4 } },
      )
      assert_equal(uri.to_s, server.pop_response.response.first.attributes[:uri])
    end
  end

  def test_does_nothing_when_declaration_does_not_exist
    source = <<~RUBY
      # typed: false

      class A
        def bar
          foo
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 4 } },
      )
      assert_empty(server.pop_response.response)
    end
  end

  private

  def create_definition_addon
    Class.new(RubyLsp::Addon) do
      def create_definition_listener(response_builder, uri, nesting, dispatcher)
        klass = Class.new do
          def initialize(response_builder, uri, _, dispatcher)
            @uri = uri
            @response_builder = response_builder
            dispatcher.register(self, :on_constant_read_node_enter)
          end

          def on_constant_read_node_enter(node)
            location = node.location
            @response_builder << RubyLsp::Interface::Location.new(
              uri: "file:///generated_by_addon.rb",
              range: RubyLsp::Interface::Range.new(
                start: RubyLsp::Interface::Position.new(
                  line: location.start_line - 1,
                  character: location.start_column,
                ),
                end: RubyLsp::Interface::Position.new(line: location.end_line - 1, character: location.end_column),
              ),
            )
          end
        end

        T.unsafe(klass).new(response_builder, uri, nesting, dispatcher)
      end

      def activate(global_state, message_queue); end

      def deactivate; end

      def name; end
    end
  end
end
