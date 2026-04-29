# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class HoverExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Hover, "hover"

  # Skip add-on loading by default — only test_hover_addons needs it
  def with_server(source = nil, uri = Kernel.URI("file:///fake.rb"), stub_no_typechecker: false, load_addons: false,
    &block)
    super
  end

  def run_expectations(source)
    position = @__params&.first || { character: 0, line: 0 }

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # We need to pretend that Sorbet is not a dependency or else we can't properly test
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: position },
      )
      server.pop_response.response
    end
  end

  def test_hovering_over_private_constant_from_the_same_namespace
    source = <<~RUBY
      class A
        CONST = 123
        private_constant(:CONST)

        CONST
      end
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 2, line: 4 } },
      )

      assert_match("CONST", server.pop_response.response.contents.value)
    end
  end

  def test_hovering_on_erb
    source = <<~ERB
      <% Person %>
    ERB

    with_server(source, Kernel.URI("file:///fake.erb"), stub_no_typechecker: true) do |server, uri|
      graph = server.global_state.graph
      graph.index_source(URI::Generic.from_path(path: "/person.rb").to_s, <<~RUBY, "ruby")
        # Hello from person.rb
        class Person
        end
      RUBY
      graph.resolve

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { line: 0, character: 4 } },
      )
      response = server.pop_response
      assert_match(/Hello from person\.rb/, response.response.contents.value)
    end
  end

  def test_hovering_for_global_variables
    source = <<~RUBY
      # and write node
      $bar &&= 1
      # operator write node
      $baz += 1
      # or write node
      $qux ||= 1
      # target write node
      $quux, $corge = 1
      # foo docs
      $foo = 1
      $foo
    RUBY

    expectations = [
      { line: 1, documentation: "and write node" },
      { line: 3, documentation: "operator write node" },
      { line: 5, documentation: "or write node" },
      { line: 7, documentation: "target write node" },
      { line: 9, documentation: "foo docs" },
      { line: 10, documentation: "foo docs" },
    ]

    with_server(source) do |server, uri|
      expectations.each do |expectation|
        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: expectation[:line], character: 1 } },
        )

        assert_match(expectation[:documentation], server.pop_response.response.contents.value)
      end
    end
  end

  def test_hover_apply_target_correction
    source = <<~RUBY
      $bar &&= 1
      $baz += 1
      $qux ||= 1
      $foo = 1
    RUBY

    lines_with_target_correction = [0, 1, 2, 3]

    with_server(source) do |server, uri|
      lines_with_target_correction.each do |line|
        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: {
            textDocument: { uri: uri },
            position: { line: line, character: 5 },
          },
        )

        assert_nil(server.pop_response.response)
      end
    end
  end

  def test_hovering_precision
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
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 0 } },
      )
      assert_match(/Foo\b/, server.pop_response.response.contents.value)

      # Foo::Bar
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 5 } },
      )
      assert_match(/Foo::Bar\b/, server.pop_response.response.contents.value)

      # Foo::Bar::Baz
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { line: 7, character: 10 } },
      )
      assert_match(/Foo::Bar::Baz\b/, server.pop_response.response.contents.value)
    end
  end

  def test_hovering_methods_invoked_on_implicit_self
    source = <<~RUBY
      # typed: false

      class A
        # Hello from `foo`
        def foo; end

        def bar
          foo
        end
      end
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 7 } },
      )

      assert_match("Hello from `foo`", server.pop_response.response.contents.value)
    end
  end

  def test_hovering_methods_with_two_definitions
    source = <<~RUBY
      # typed: false

      class A
        # Hello from first `foo`
        def foo; end

        def bar
          foo
        end
      end

      class A
        # Hello from second `foo`
        def foo; end
      end
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 7 } },
      )

      response = server.pop_response.response
      assert_match("Hello from first `foo`", response.contents.value)
      assert_match("Hello from second `foo`", response.contents.value)
    end
  end

  def test_hovering_methods_invoked_on_explicit_self
    source = <<~RUBY
      # typed: false

      class A
        # Hello from `foo`
        def foo; end

        def bar
          self.foo
        end
      end
    RUBY

    # We need to pretend that Sorbet is not a dependency or else we can't properly test
    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 9, line: 7 } },
      )

      assert_match("Hello from `foo`", server.pop_response.response.contents.value)
    end
  end

  def test_hovering_over_private_constant_from_different_namespace
    source = <<~RUBY
      class A
        CONST = 123
        private_constant(:CONST)
      end

      A::CONST
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 3, line: 5 } },
      )

      # TODO: once we have visibility exposed from Rubydex, let's show that the constant is private
      assert_match("A::CONST", server.pop_response.response.contents.value)
    end
  end

  def test_hovering_over_gemfile_dependency_name
    source = <<~RUBY
      gem 'rake'
    RUBY

    with_server(source, URI("file:///Gemfile")) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 5, line: 0 } },
      )

      response = server.pop_response.response
      spec = Gem.loaded_specs["rake"]

      assert_includes(response.contents.value, spec.name)
      assert_includes(response.contents.value, spec.version.to_s)
      assert_includes(response.contents.value, spec.homepage)
    end
  end

  def test_hovering_over_gemfile_dependency_triggers_only_for_first_arg
    source = <<~RUBY
      gem 'rake', '~> 1.0'
    RUBY

    with_server(source, URI("file:///Gemfile")) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 13, line: 0 } },
      )

      response = server.pop_response.response

      assert_nil(response)
    end
  end

  def test_hovering_over_gemfile_dependency_with_missing_argument
    source = <<~RUBY
      gem()
    RUBY

    with_server(source, URI("file:///Gemfile")) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 0 } },
      )

      assert_nil(server.pop_response.response)
    end
  end

  def test_hovering_over_gemfile_dependency_with_non_gem_argument
    source = <<~RUBY
      gem(method_call)
    RUBY

    with_server(source, URI("file:///Gemfile")) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 0 } },
      )

      assert_nil(server.pop_response.response)
    end
  end

  def test_hover_addons
    source = <<~RUBY
      # Hello
      class Post
      end

      Post
    RUBY

    begin
      create_hover_addon

      with_server(source, stub_no_typechecker: true, load_addons: true) do |server, uri|
        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { character: 0, line: 4 } },
        )

        assert_match(<<~RESPONSE.strip, server.pop_response.response.contents.value)
          Title

          **Definitions**: [fake.rb](file:///fake.rb#L2,1-3,4)
          Links



          Hello
          Documentation from middleware: Post
        RESPONSE
      end
    ensure
      RubyLsp::Addon.addon_classes.clear
    end
  end

  def test_hover_precision_for_methods_with_block_arguments
    source = <<~RUBY
      class Foo
        # Hello
        def foo(&block); end

        def bar
          foo(&:argument)
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 12, line: 5 } },
      )
      # Hover on `argument` should not show you the `foo` documentation
      assert_nil(server.pop_response.response)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 5 } },
      )
      assert_match("Hello", server.pop_response.response.contents.value)
    end
  end

  def test_hover_instance_variables
    source = <<~RUBY
      class Foo
        def initialize
          # Hello
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
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 7 } },
      )
      assert_match("Hello", server.pop_response.response.contents.value)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 11 } },
      )
      assert_match("Hello", server.pop_response.response.contents.value)
    end
  end

  def test_hovering_for_class_variables
    source = <<~RUBY
      class Foo
        def foo
          # or write node
          @@a ||= 1
        end

        def bar
          # operator write node
          @@a += 5
        end

        def baz
          @@a
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 6, line: 12 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("or write node", contents)
      assert_match("operator write node", contents)
    end
  end

  def test_hovering_for_inherited_class_variables
    source = <<~RUBY
      module Foo
        def set_variable
          # Foo
          @@bar = 1
        end
      end

      class Parent
        def set_variable
          # Parent
          @@bar = 5
        end
      end

      class Child < Parent
        include Foo

        def do_something
          @@bar
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 18 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Foo", contents)
      assert_match("Parent", contents)
    end
  end

  def test_hovering_for_class_variables_in_different_context
    source = <<~RUBY
      class Foo
        # comment 1
        @@a = 1

        class << self
          # comment 2
          @@a = 2

          def foo
            # comment 3
            @@a = 3
          end
        end

        def bar
          # comment 4
          @@a = 4
        end

        def self.baz
          # comment 5
          @@a = 5
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 2 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("comment 1", contents)
      assert_match("comment 2", contents)
      assert_match("comment 3", contents)
      assert_match("comment 4", contents)
      assert_match("comment 5", contents)
    end
  end

  def test_hovering_over_inherited_methods
    source = <<~RUBY
      module Foo
        module First
          # Method 1
          def method1; end
        end

        class Bar
          # Method 2
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

    # Going to definition on `argument` should not take you to the `foo` method definition
    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 6, line: 15 } },
      )
      assert_match("Method 1", server.pop_response.response.contents.value)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 6, line: 16 } },
      )
      assert_match("Method 2", server.pop_response.response.contents.value)
    end
  end

  def test_hover_for_inherited_instance_variables
    source = <<~RUBY
      module Foo
        def set_ivar
          # Foo
          @a = 1
        end
      end

      class Parent
        def initialize
          # Parent
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
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 18 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Foo", contents)
      assert_match("Parent", contents)
    end
  end

  def test_hover_for_methods_shows_parameters
    source = <<~RUBY
      class Foo
        def bar(a, b = 1, *c, d:, e: 1, **f, &g)
        end

        def baz
          bar
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 5 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("bar(a, b = <default>, *c, d:, e: <default>, **f, &g)", contents)
    end
  end

  def test_hover_for_methods_shows_overload_count
    skip("[RUBYDEX] Temporarily skipped because we don't yet index RBS methods")

    source = <<~RUBY
      String.try_convert
    RUBY

    with_server(source) do |server, uri|
      index = server.instance_variable_get(:@global_state).index
      RubyIndexer::RBSIndexer.new(index).index_ruby_core
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 8, line: 0 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("try_convert(object)", contents)
      assert_match("(+2 overloads)", contents)
    end
  end

  def test_hover_for_singleton_methods
    source = <<~RUBY
      class Foo
        # bar
        def self.bar
        end

        class << self
          # baz
          def baz; end
        end
      end

      Foo.bar
      Foo.baz
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 11 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("bar", contents)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 12 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("baz", contents)
    end
  end

  def test_definition_for_class_instance_variables
    source = <<~RUBY
      class Foo
        # Hey!
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
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 5 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Hey!", contents)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 6, line: 10 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Hey!", contents)
    end
  end

  def test_hover_for_aliased_methods
    source = <<~RUBY
      class Parent
        # Original
        def bar; end
      end

      class Child < Parent
        # Alias
        alias baz bar

        def do_something
          baz
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 10 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Alias", contents)
      assert_match("Original", contents)
    end
  end

  def test_hover_for_super_calls
    source = <<~RUBY
      class Parent
        # Foo
        def foo; end
        # Bar
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
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 9 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Foo", contents)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 13 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Bar", contents)
    end
  end

  def test_hover_is_disabled_for_self_methods_on_typed_true
    source = <<~RUBY
      # typed: true
      class Child
        def foo
          bar
        end

        # Hey!
        def bar
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 3 } },
      )

      assert_nil(server.pop_response.response)
    end
  end

  def test_hover_is_disabled_for_instance_variables_on_typed_strict
    source = <<~RUBY
      # typed: strict
      class Child
        def initialize
          # Hello
          @something = 123 #: Integer
        end

        def bar
          @something
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 8 } },
      )

      assert_nil(server.pop_response.response)
    end
  end

  def test_hover_on_super_for_typed_true_shows_keyword_doc_only
    source = <<~RUBY
      # typed: true
      class Parent
        def foo; end
      end
      class Child < Parent
        def foo
          super
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 6 } },
      )

      response = server.pop_response.response
      refute_nil(response)

      contents = response.contents.value
      refute_match("foo", contents)
      assert_match("```ruby\nsuper\n```", contents)
    end
  end

  def test_hover_for_guessed_receivers
    source = <<~RUBY
      class User
        def name; end
      end

      user.name
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 5, line: 4 } },
      )

      contents = server.pop_response.response.contents.value
      assert_match("Guessed receiver: User", contents)
      assert_match("Learn more about guessed types", contents)
    end
  end

  def test_hover_for_keywords
    test_cases = {
      "BEGIN" => { source: "BEGIN { }" },
      "END" => { source: "END { }" },
      "__ENCODING__" => { source: "__ENCODING__" },
      "__FILE__" => { source: "__FILE__" },
      "__LINE__" => { source: "__LINE__" },
      "alias" => { source: "alias foo bar" },
      "and" => { source: "true and false", position: { character: 5, line: 0 } },
      "begin" => { source: "begin\nend" },
      "break" => { source: "break" },
      "case" => { source: "case 1\nwhen 1\nend" },
      "class" => { source: "class A\nend" },
      "def" => { source: "def foo\nend" },
      "defined?" => { source: "defined?(x)" },
      "do" => { source: "proc do\nend", position: { character: 5, line: 0 } },
      "else" => { source: "if true\nelse\nend", position: { character: 0, line: 1 } },
      "ensure" => { source: "begin\nensure\nend", position: { character: 0, line: 1 } },
      "false" => { source: "false" },
      "for" => { source: "for x in [1]\nend" },
      "if" => { source: "if true\nend" },
      "in" => { source: "case x\nin 1\nend", position: { character: 0, line: 1 } },
      "module" => { source: "module A\nend" },
      "next" => { source: "next" },
      "nil" => { source: "nil" },
      "or" => { source: "true or false", position: { character: 5, line: 0 } },
      "redo" => { source: "redo" },
      "rescue" => { source: "begin\nrescue\nend", position: { character: 0, line: 1 } },
      "retry" => { source: "retry" },
      "return" => { source: "return" },
      "self" => { source: "self" },
      "true" => { source: "true" },
      "undef" => { source: "undef :foo" },
      "unless" => { source: "unless true\nend" },
      "until" => { source: "until true\nend" },
      "when" => { source: "case x\nwhen 1\nend", position: { character: 0, line: 1 } },
      "while" => { source: "while true\nend" },
      "yield" => { source: "yield" },
    }

    test_cases.each do |keyword, config|
      position = config[:position] || { character: 0, line: 0 }

      with_server(config[:source]) do |server, uri|
        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: {
            textDocument: { uri: uri },
            position: position,
          },
        )

        graph = server.global_state.graph
        response = server.pop_response.response
        refute_nil(response, "expected hover response for keyword `#{keyword}`")
        contents = response.contents.value
        assert_match("```ruby\n#{keyword}\n```", contents)
        assert_match(graph.keyword(keyword).documentation, contents)
      end
    end
  end

  def test_hover_does_not_show_keyword_doc_on_constant_path_of_class
    source = "class Foo\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `Foo`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 7, line: 0 } },
      )

      contents = server.pop_response.response.contents.value
      refute_match("```ruby\nclass\n```", contents)
      assert_match("Foo", contents)
    end
  end

  def test_hover_does_not_show_keyword_doc_on_constant_path_of_module
    source = "module Foo\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `Foo`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 8, line: 0 } },
      )

      contents = server.pop_response.response.contents.value
      refute_match("```ruby\nmodule\n```", contents)
      assert_match("Foo", contents)
    end
  end

  def test_hover_does_not_show_keyword_doc_on_nested_constant_path
    source = "class Foo::Bar\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `Foo`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 7, line: 0 } },
      )
      contents = server.pop_response.response.contents.value
      refute_match("```ruby\nclass\n```", contents)

      # cursor on `Bar`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 12, line: 0 } },
      )
      contents = server.pop_response.response.contents.value
      refute_match("```ruby\nclass\n```", contents)
    end
  end

  def test_hover_does_not_show_keyword_doc_on_superclass
    source = "class Bar\nend\nclass Foo < Bar\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `Bar` (the superclass)
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 13, line: 2 } },
      )
      contents = server.pop_response.response.contents.value
      refute_match("```ruby\nclass\n```", contents)
      assert_match("Bar", contents)
    end
  end

  def test_hover_does_not_show_and_keyword_doc_on_double_ampersand_operator
    source = "true && false"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `&&`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 5, line: 0 } },
      )
      assert_nil(server.pop_response.response)
    end
  end

  def test_hover_does_not_show_or_keyword_doc_on_double_pipe_operator
    source = "true || false"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `||`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 5, line: 0 } },
      )
      assert_nil(server.pop_response.response)
    end
  end

  def test_hover_does_not_show_do_keyword_doc_on_brace_block
    source = "proc { 1 }"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `{`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 5, line: 0 } },
      )
      assert_nil(server.pop_response.response)
    end
  end

  def test_hover_does_not_show_keyword_doc_on_ternary_punctuation
    source = "x ? 1 : 2"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `?`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 2, line: 0 } },
      )
      assert_nil(server.pop_response.response)

      # cursor on `:`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 6, line: 0 } },
      )
      assert_nil(server.pop_response.response)
    end
  end

  def test_hover_on_end_shows_end_keyword_doc_for_class
    source = "class Foo\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `end`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 1 } },
      )
      response = server.pop_response.response
      refute_nil(response)
      contents = response.contents.value
      assert_match("```ruby\nend\n```", contents)
      refute_match("```ruby\nclass\n```", contents)
    end
  end

  def test_hover_on_end_shows_end_keyword_doc_for_def
    source = "def foo\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `end`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 1 } },
      )
      response = server.pop_response.response
      refute_nil(response)
      contents = response.contents.value
      assert_match("```ruby\nend\n```", contents)
      refute_match("```ruby\ndef\n```", contents)
    end
  end

  def test_hover_on_end_shows_end_keyword_doc_for_if
    source = "if true\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `end`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 1 } },
      )
      response = server.pop_response.response
      refute_nil(response)
      contents = response.contents.value
      assert_match("```ruby\nend\n```", contents)
      refute_match("```ruby\nif\n```", contents)
    end
  end

  def test_hover_on_elsif_shows_elsif_keyword_doc
    source = "if a\nelsif b\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `elsif`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 1 } },
      )
      response = server.pop_response.response
      refute_nil(response)
      contents = response.contents.value
      assert_match("```ruby\nelsif\n```", contents)
      refute_match("```ruby\nif\n```", contents)
    end
  end

  def test_hover_shows_class_keyword_doc_for_singleton_class
    source = "class << self\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `class`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 0 } },
      )

      response = server.pop_response.response
      refute_nil(response)
      assert_match("```ruby\nclass\n```", response.contents.value)
    end
  end

  def test_hover_shows_end_keyword_doc_for_singleton_class
    source = "class << self\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `end`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 1 } },
      )

      response = server.pop_response.response
      refute_nil(response)
      assert_match("```ruby\nend\n```", response.contents.value)
    end
  end

  def test_hover_shows_do_keyword_doc_for_lambda
    source = "-> do\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `do`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 3, line: 0 } },
      )

      response = server.pop_response.response
      refute_nil(response)
      assert_match("```ruby\ndo\n```", response.contents.value)
    end
  end

  def test_hover_shows_end_keyword_doc_for_lambda
    source = "-> do\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `end`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 1 } },
      )

      response = server.pop_response.response
      refute_nil(response)
      assert_match("```ruby\nend\n```", response.contents.value)
    end
  end

  def test_hover_does_not_show_keyword_doc_on_lambda_operator_or_braces
    with_server("-> { }", stub_no_typechecker: true) do |server, uri|
      # cursor on `->`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 0 } },
      )
      assert_nil(server.pop_response.response)

      # cursor on `{`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 3, line: 0 } },
      )
      assert_nil(server.pop_response.response)
    end
  end

  def test_hover_shows_not_keyword_doc
    source = "not true"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `not`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 0 } },
      )

      response = server.pop_response.response
      refute_nil(response)
      assert_match("```ruby\nnot\n```", response.contents.value)
    end
  end

  def test_hover_on_forwarding_super_shows_method_doc_and_keyword_doc
    source = <<~RUBY
      class Parent
        # Parent greeting
        def greet
        end
      end

      class Child < Parent
        def greet
          super
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `super`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 8 } },
      )

      response = server.pop_response.response
      refute_nil(response)
      contents = response.contents.value

      assert_match("greet", contents)
      assert_match("```ruby\nsuper\n```", contents)
    end
  end

  def test_hover_on_super_call_shows_method_doc_and_keyword_doc
    source = <<~RUBY
      class Parent
        def greet(name)
        end
      end

      class Child < Parent
        def greet(name)
          super(name)
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      # cursor on `super` of `super(name)`
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 7 } },
      )

      response = server.pop_response.response
      refute_nil(response)

      contents = response.contents.value
      assert_match("greet", contents)
      assert_match("```ruby\nsuper\n```", contents)
    end
  end

  def test_hover_on_end_shows_end_keyword_doc_for_module
    source = "module Foo\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 1 } },
      )

      response = server.pop_response.response
      refute_nil(response)
      assert_match("```ruby\nend\n```", response.contents.value)
    end
  end

  def test_hover_on_end_shows_end_keyword_doc_for_while
    source = "while true\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 1 } },
      )

      response = server.pop_response.response
      refute_nil(response)
      assert_match("```ruby\nend\n```", response.contents.value)
    end
  end

  def test_hover_on_end_shows_end_keyword_doc_for_begin_ensure
    source = "begin\nensure\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 2 } },
      )

      response = server.pop_response.response
      refute_nil(response)
      assert_match("```ruby\nend\n```", response.contents.value)
    end
  end

  def test_hover_on_end_shows_end_keyword_doc_for_if_else
    source = "if true\nelse\nend"

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 2 } },
      )

      response = server.pop_response.response
      refute_nil(response)
      assert_match("```ruby\nend\n```", response.contents.value)
    end
  end

  def test_hover_call_node_precision
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
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 19, line: 8 } },
      )
      assert_nil(server.pop_response.response)

      # On `message`, we should
      server.process_message(
        id: 2,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 23, line: 8 } },
      )
      refute_nil(server.pop_response.response)
    end
  end

  def test_hovering_constants_shows_complete_name
    source = <<~RUBY
      # typed: ignore
      module Foo
        CONST = 123

        module Bar
          class Baz; end

          Baz
        end
      end

      QUX = 42
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 4, line: 7 } },
      )
      assert_match("```ruby\nFoo::Bar::Baz\n```", server.pop_response.response.contents.value)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 2, line: 2 } },
      )
      assert_match("```ruby\nFoo::CONST\n```", server.pop_response.response.contents.value)

      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { character: 0, line: 11 } },
      )
      assert_match("```ruby\nQUX\n```", server.pop_response.response.contents.value)
    end
  end

  private

  def create_hover_addon
    Class.new(RubyLsp::Addon) do
      def activate(global_state, outgoing_queue); end

      def name
        "HoverAddon"
      end

      def deactivate; end

      def version
        "0.1.0"
      end

      def create_hover_listener(response_builder, nesting, dispatcher)
        klass = Class.new do
          def initialize(response_builder, dispatcher)
            @response_builder = response_builder
            dispatcher.register(self, :on_constant_read_node_enter)
          end

          def on_constant_read_node_enter(node)
            @response_builder.push(
              "Documentation from middleware: #{node.slice}", category: :documentation
            )
            @response_builder.push(
              "Links", category: :links
            )
            @response_builder.push(
              "Title", category: :title
            )
          end
        end

        klass.new(response_builder, dispatcher)
      end
    end
  end
end
