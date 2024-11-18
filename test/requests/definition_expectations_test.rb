# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

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

          case location
          when RubyLsp::Interface::LocationLink
            fake_path = T.let(attributes[:targetUri].split("/").last(2).join("/"), String)
            location.instance_variable_set(:@attributes, attributes.merge("targetUri" => "file:///#{fake_path}"))
          else
            fake_path = T.let(attributes[:uri].split("/").last(2).join("/"), String)
            location.instance_variable_set(:@attributes, attributes.merge("uri" => "file:///#{fake_path}"))
          end
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

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # Foo
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 0 } },
      )
      range = server.pop_response.response[0].attributes[:targetRange].attributes
      range_hash = { start: range[:start].to_hash, end: range[:end].to_hash }
      assert_equal({ start: { line: 0, character: 0 }, end: { line: 5, character: 3 } }, range_hash)

      # Foo::Bar
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 5 } },
      )
      range = server.pop_response.response[0].attributes[:targetRange].attributes
      range_hash = { start: range[:start].to_hash, end: range[:end].to_hash }
      assert_equal({ start: { line: 1, character: 2 }, end: { line: 4, character: 5 } }, range_hash)

      # Foo::Bar::Baz
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 10 } },
      )
      range = server.pop_response.response[0].attributes[:targetRange].attributes
      range_hash = { start: range[:start].to_hash, end: range[:end].to_hash }
      assert_equal({ start: { line: 2, character: 4 }, end: { line: 3, character: 7 } }, range_hash)
    end
  end

  def test_multibyte_character_precision
    source = <<~RUBY
      module Fほげ
        module Bar
          class Baz
          end
        end
      end

      Fほげ::Bar::Baz
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # Foo
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 0 } },
      )
      range = server.pop_response.response[0].attributes[:targetRange].attributes
      range_hash = { start: range[:start].to_hash, end: range[:end].to_hash }
      assert_equal({ start: { line: 0, character: 0 }, end: { line: 5, character: 3 } }, range_hash)
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

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 2, line: 4 } },
      )
      response = server.pop_response

      assert_instance_of(RubyLsp::Result, response)
      assert_equal(uri.to_s, response.response.first.attributes[:targetUri])
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

    begin
      create_definition_addon

      with_server(source, stub_no_typechecker: true) do |server, uri|
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
        assert_match("class_reference_target.rb", response[0].target_uri)
        assert_match("generated_by_addon.rb", response[1].uri)
      end
    ensure
      RubyLsp::Addon.addon_classes.clear
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
      assert_equal(uri.to_s, server.pop_response.response.first.attributes[:targetUri])
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
            languageId: "ruby",
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
      assert_equal(uri.to_s, first_definition.attributes[:targetUri])
      assert_equal(second_uri.to_s, second_definition.attributes[:targetUri])
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
      assert_equal(uri.to_s, server.pop_response.response.first.attributes[:targetUri])
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

  def test_jumping_to_autoload_definition_when_declaration_exists
    source = <<~RUBY
      # typed: ignore

      class Foo
        autoload :Bar, "bar"
      end
    RUBY

    with_server(source) do |server, uri|
      server.global_state.index.index_single(
        RubyIndexer::IndexablePath.new(nil, "/fake/path/bar.rb"), <<~RUBY
          class Foo::Bar; end
        RUBY
      )
      server.global_state.index.index_single(
        RubyIndexer::IndexablePath.new(nil, "/fake/path/baz.rb"), <<~RUBY
          class Foo::Bar; end
        RUBY
      )
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 12, line: 3 } },
      )

      response = server.pop_response.response
      # This feature simply does a constant lookup on the symbol passed to autoload, instead of jumping into the
      # autoloaded path
      # This is because there's no guarantee that the autoloaded file actually defines the constant. But if it does,
      # then it will be listed in the result anyway
      assert_equal(2, response.size)
      assert_equal("file:///fake/path/bar.rb", response.first.attributes[:targetUri])
      assert_equal("file:///fake/path/baz.rb", response.last.attributes[:targetUri])
    end
  end

  def test_does_nothing_when_autoload_declaration_does_not_exist
    source = <<~RUBY
      # typed: ignore

      class Foo
        autoload :Bar, "bar"
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 3, line: 3 } },
      )
      assert_empty(server.pop_response.response)
    end
  end

  def test_methods_with_dynamic_namespace_is_also_suggested
    source = <<~RUBY
      # typed: false

      class self::A
        def foo; end

        def bar
          foo
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 6 } },
      )
      response = server.pop_response.response

      assert_equal(1, response.size)

      range = response[0].attributes[:targetRange].attributes
      range_hash = { start: range[:start].to_hash, end: range[:end].to_hash }
      assert_equal({ start: { line: 3, character: 2 }, end: { line: 3, character: 14 } }, range_hash)
    end
  end

  def test_definitions_are_listed_for_method_with_unknown_receiver
    source = <<~RUBY
      # typed: false

      class A
        def foo; end
      end

      class B
        def foo; end
      end

      obj.foo
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 10 } },
      )
      response = server.pop_response.response

      assert_equal(2, response.size)

      range = response[0].attributes[:targetRange].attributes
      range_hash = { start: range[:start].to_hash, end: range[:end].to_hash }
      assert_equal({ start: { line: 3, character: 2 }, end: { line: 3, character: 14 } }, range_hash)

      range = response[1].attributes[:targetRange].attributes
      range_hash = { start: range[:start].to_hash, end: range[:end].to_hash }
      assert_equal({ start: { line: 7, character: 2 }, end: { line: 7, character: 14 } }, range_hash)
    end
  end

  def test_definition_for_guessed_receiver_is_listed
    source = <<~RUBY
      # typed: false

      class Cheetah
        def meow; end
      end

      class Cat
        def meow; end
      end

      cat = Cat.new
      cat.meow
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 11 } },
      )
      response = server.pop_response.response

      # Only Cat#meow is listed
      assert_equal(1, response.size)
      assert_equal(7, response.first.target_range.start.line)
      assert_equal(7, response.first.target_range.end.line)
      assert_equal(2, response.first.target_range.start.character)
      assert_equal(15, response.first.target_range.end.character)
    end
  end

  def test_guessed_receiver_is_treated_as_unknown_when_no_declaration_exists
    source = <<~RUBY
      # typed: false

      class Animal
        def eat; end
      end

      class Cheetah
        def meow; end
      end

      class Cat
        def meow; end
      end

      animal = Cat.new
      animal.meow
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 7, line: 15 } },
      )
      response = server.pop_response.response

      assert_equal(2, response.size)
    end
  end

  def test_definitions_for_unknown_receiver_is_capped
    source = +"# typed: false\n"

    13.times do |i|
      source << <<~RUBY
        class Class#{i + 1}
          def foo; end
        end
      RUBY
    end
    source << "\nobj.foo"

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 41 } },
      )
      response = server.pop_response.response

      assert_equal(10, response.size)
    end
  end

  def test_definitions_are_listed_in_erb_files_as_unknown_receiver
    source = <<~ERB
      <%= foo %>
    ERB

    with_server(source, URI("/fake.erb")) do |server, uri|
      server.global_state.index.index_single(
        RubyIndexer::IndexablePath.new(nil, "/fake/path/foo.rb"), <<~RUBY
          class Bar
            def foo; end

            def bar; end
          end
        RUBY
      )

      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 0 } },
      )
      response = server.pop_response.response

      assert_equal(1, response.size)

      range = response[0].attributes[:targetRange].attributes
      range_hash = { start: range[:start].to_hash, end: range[:end].to_hash }
      assert_equal({ start: { line: 1, character: 2 }, end: { line: 1, character: 14 } }, range_hash)
    end
  end

  def test_definition_precision_for_methods_with_block_arguments
    source = <<~RUBY
      class Foo
        def foo(&block); end

        def argument; end
      end

      bar.foo(&:argument)
    RUBY

    # Going to definition on `argument` should not take you to the `foo` method definition
    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 12, line: 6 } },
      )
      assert_equal(3, server.pop_response.response.first.target_range.start.line)

      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 6 } },
      )
      assert_equal(1, server.pop_response.response.first.target_range.start.line)
    end
  end

  def test_definition_for_method_call_inside_arguments
    source = <<~RUBY
      class Foo
        def foo; end

        def bar(a:, b:); end

        def baz
          bar(a: foo, b: 42)
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 11, line: 6 } },
      )
      response = server.pop_response.response.first
      assert_equal(1, response.target_range.start.line)
      assert_equal(1, response.target_range.end.line)
    end
  end

  def test_definition_for_global_variables
    source = <<~RUBY
      $bar &&= 1
      $bar += 1
      $foo ||= 1
      $bar, $foo = 1
      $foo = 1
      $DEBUG
    RUBY

    with_server(source) do |server, uri|
      index = server.instance_variable_get(:@global_state).index
      RubyIndexer::RBSIndexer.new(index).index_ruby_core

      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 1, line: 0 } },
      )

      response = server.pop_response.response
      assert_equal(3, response.size)
      assert_equal(0, response[0].range.start.line)
      assert_equal(1, response[1].range.start.line)
      assert_equal(3, response[2].range.start.line)

      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 1, line: 2 } },
      )

      response = server.pop_response.response
      assert_equal(3, response.size)
      assert_equal(2, response[0].range.start.line)
      assert_equal(3, response[1].range.start.line)
      assert_equal(4, response[2].range.start.line)

      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 1, line: 5 } },
      )

      response = server.pop_response.response.first
      assert_match(%r{/gems/rbs-.*/core/global_variables.rbs}, response.uri)
      assert_equal(response.range.start.line, response.range.end.line)
      assert_operator(response.range.start.character, :<, response.range.end.character)
    end
  end

  def test_definition_apply_target_correction
    source = <<~RUBY
      $foo &&= 1
      $foo += 1
      $foo ||= 1
      $foo = 1
      class Foo
        @foo &&= 1
        @foo += 1
        @foo ||= 1
        @foo = 1
      end
    RUBY

    lines_with_target_correction = [0, 1, 2, 3, 5, 6, 7, 8]

    with_server(source) do |server, uri|
      lines_with_target_correction.each do |line|
        server.process_message(
          id: 1,
          method: "textDocument/definition",
          params: { textDocument: { uri: uri }, position: { character: 7, line: line } },
        )

        assert_empty(server.pop_response.response)
      end
    end
  end

  def test_definition_for_instance_variables
    source = <<~RUBY
      class Foo
        def initialize
          @a = 1
        end

        def bar
          @a
        end

        def baz
          @a = 5
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 6 } },
      )
      response = server.pop_response.response.first
      assert_equal(2, response.range.start.line)

      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 10 } },
      )
      response = server.pop_response.response.first
      assert_equal(2, response.range.start.line)
    end
  end

  def test_definition_for_inherited_methods
    source = <<~RUBY
      module Foo
        module First
          def method1; end
        end

        class Bar
          def method2; end
        end

        class Baz < Bar
          include First

          def method3
            method1
            method2
          end
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 6, line: 13 } },
      )
      response = server.pop_response.response.first
      assert_equal(2, response.target_range.start.line)

      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 6, line: 14 } },
      )
      response = server.pop_response.response.first
      assert_equal(6, response.target_range.start.line)
    end
  end

  def test_definition_for_inherited_instance_variables
    source = <<~RUBY
      module Foo
        def set_ivar
          @a = 1
        end
      end

      class Parent
        def initialize
          @a = 5
        end
      end

      class Child < Parent
        include Foo

        def do_something
          @a
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 16 } },
      )
      response = server.pop_response.response

      # First location is Foo#@a
      assert_equal(2, response[0].range.start.line)
      # Second location is Parent#@a
      assert_equal(8, response[1].range.start.line)
    end
  end

  def test_definition_for_singleton_methods
    source = <<~RUBY
      class Foo
        def self.bar
        end

        class << self
          def baz; end
        end
      end

      Foo.bar
      Foo.baz
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 9 } },
      )

      response = server.pop_response.response
      assert_equal(1, response[0].target_range.start.line)

      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 10 } },
      )

      response = server.pop_response.response
      assert_equal(5, response[0].target_range.start.line)
    end
  end

  def test_definition_for_class_instance_variables
    source = <<~RUBY
      class Foo
        @a = 123

        def self.bar
          @a
        end

        class << self
          def baz
            @a
          end
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 4 } },
      )

      response = server.pop_response.response
      assert_equal(1, response[0].range.start.line)

      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 6, line: 9 } },
      )

      response = server.pop_response.response
      assert_equal(1, response[0].range.start.line)
    end
  end

  def test_definition_for_aliased_methods
    source = <<~RUBY
      class Parent
        def bar; end
      end

      class Child < Parent
        alias baz bar

        def do_something
          baz
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 8 } },
      )
      response = server.pop_response.response

      assert_equal(5, response[0].target_range.start.line)
    end
  end

  def test_definition_for_super_calls
    source = <<~RUBY
      class Parent
        def foo; end
        def bar; end
      end

      class Child < Parent
        def foo(a)
          super()
        end

        def bar
          super
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 7 } },
      )

      response = server.pop_response.response
      assert_equal(1, response[0].target_range.start.line)

      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 11 } },
      )

      response = server.pop_response.response
      assert_equal(2, response[0].target_range.start.line)
    end
  end

  def test_definition_for_super_calls_is_disabled_on_typed_true
    source = <<~RUBY
      # typed: true
      class Parent
        def foo; end
        def bar; end
      end

      class Child < Parent
        def foo(a)
          super()
        end

        def bar
          super
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 8 } },
      )

      assert_empty(server.pop_response.response)

      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 12 } },
      )

      assert_empty(server.pop_response.response)
    end
  end

  def test_definition_on_self_is_disabled_for_typed_true
    # We need this expectation to make sure the test is testing the early return inside on_call_node_enter
    # not the one inside handle_method_definition
    RubyLsp::Listeners::Definition.any_instance.expects(:not_in_dependencies?).never

    source = <<~RUBY
      # typed: true
      class Foo
        def bar
          baz
        end

        def baz
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 3 } },
      )

      assert_empty(server.pop_response.response)
    end
  end

  def test_definition_for_instance_variables_is_disabled_on_typed_strict
    source = <<~RUBY
      # typed: strict
      class Foo
        def initialize
          @something = T.let(123, Integer)
        end

        def baz
          @something
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 7 } },
      )

      assert_empty(server.pop_response.response)
    end
  end

  def test_definition_call_node_precision
    source = <<~RUBY
      class Foo
        def message
          "hello!"
        end
      end

      class Bar
        def with_foo(foo)
          @foo_message = foo.message
        end
      end
    RUBY

    with_server(source) do |server, uri|
      # On the `foo` receiver, we should not show any results
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 19, line: 8 } },
      )
      assert_empty(server.pop_response.response)

      # On `message`, we should
      server.process_message(
        id: 2,
        method: "textDocument/definition",
        params: { textDocument: { uri: uri }, position: { character: 23, line: 8 } },
      )
      refute_empty(server.pop_response.response)
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

      def activate(global_state, outgoing_queue); end

      def deactivate; end

      def name; end

      def version
        "0.1.0"
      end
    end
  end
end
