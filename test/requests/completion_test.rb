# typed: true
# frozen_string_literal: true

require "test_helper"

class CompletionTest < Minitest::Test
  def test_completion_keyword
    source = <<~RUBY
      foo d
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 0, character: 5 },
        })
        result = server.pop_response.response

        assert_equal(3, result.count)
        assert_equal("def", result[0].label)
        assert_equal("defined?", result[1].label)
        assert_equal("do", result[2].label)
      end
    end
  end

  def test_completion_command
    prefix = "foo/"
    source = <<~RUBY
      require "#{prefix}"
    RUBY
    start_char = source.index('"') #: as !nil
    end_char = source.rindex('"') #: as !nil
    start_position = { line: 0, character: start_char + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 0, character: end_char },
        })
        result = server.pop_response.response

        expected = [
          path_completion("foo/bar", start_position, end_position),
          path_completion("foo/baz", start_position, end_position),
          path_completion("foo/quux", start_position, end_position),
          path_completion("foo/support/bar", start_position, end_position),
          path_completion("foo/support/baz", start_position, end_position),
          path_completion("foo/support/quux", start_position, end_position),
        ]

        assert_equal(expected.to_json, result.to_json)
      end
    end
  end

  def test_completion_call
    prefix = "foo/"
    source = <<~RUBY
      require("#{prefix}")
    RUBY
    start_char = source.index('"') #: as !nil
    end_char = source.rindex('"') #: as !nil
    start_position = { line: 0, character: start_char + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 0, character: end_char },
        })
        result = server.pop_response.response

        expected = [
          path_completion("foo/bar", start_position, end_position),
          path_completion("foo/baz", start_position, end_position),
          path_completion("foo/quux", start_position, end_position),
          path_completion("foo/support/bar", start_position, end_position),
          path_completion("foo/support/baz", start_position, end_position),
          path_completion("foo/support/quux", start_position, end_position),
        ]

        assert_equal(expected.to_json, result.to_json)
      end
    end
  end

  def test_completion_command_call
    prefix = "foo/"
    source = <<~RUBY
      Kernel.require "#{prefix}"
    RUBY
    start_char = source.index('"') #: as !nil
    end_char = source.rindex('"') #: as !nil
    start_position = { line: 0, character: start_char + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 0, character: end_char },
        })
        result = server.pop_response.response

        expected = [
          path_completion("foo/bar", start_position, end_position),
          path_completion("foo/baz", start_position, end_position),
          path_completion("foo/quux", start_position, end_position),
          path_completion("foo/support/bar", start_position, end_position),
          path_completion("foo/support/baz", start_position, end_position),
          path_completion("foo/support/quux", start_position, end_position),
        ]

        assert_equal(expected.to_json, result.to_json)
      end
    end
  end

  def test_completion_with_partial_path
    prefix = "foo/suppo"
    source = <<~RUBY
      require "#{prefix}"
    RUBY
    start_char = source.index('"') #: as !nil
    end_char = source.rindex('"') #: as !nil
    start_position = { line: 0, character: start_char + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 0, character: end_char },
        })
        result = server.pop_response.response

        expected = [
          path_completion("foo/support/bar", start_position, end_position),
          path_completion("foo/support/baz", start_position, end_position),
          path_completion("foo/support/quux", start_position, end_position),
        ]

        assert_equal(expected.to_json, result.to_json)
      end
    end
  end

  def test_completion_does_not_fail_when_there_are_syntax_errors
    source = <<~RUBY
      require "ruby_lsp/requests/"

      def foo
    RUBY
    end_position = { line: 0, character: source.rindex('"') }

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: end_position,
        })
        result = server.pop_response
        assert_instance_of(RubyLsp::Result, result)
      end
    end
  end

  def test_completion_is_not_triggered_if_argument_is_not_a_string
    source = +<<~RUBY
      require foo
    RUBY
    end_position = { line: 0, character: source.rindex("o") }

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: end_position,
        })
        result = server.pop_response.response
        assert_empty(result)
      end
    end
  end

  def test_completion_for_fully_qualified_paths_inside_namespace
    source = +<<~RUBY
      module Foo
        module Bar
          class Baz
          end

          Foo::
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 5, character: 9 },
        })
        result = server.pop_response.response
        assert_equal(["Foo::Bar", "Foo::Bar::Baz"], result.map(&:label))
      end
    end
  end

  def test_completion_for_constants
    source = +<<~RUBY
      class Foo
      end

      F
    RUBY

    end_position = { line: 3, character: 1 }

    with_server(source, stub_no_typechecker: true) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: end_position,
        })
        result = server.pop_response.response
        assert_equal(["Foo"], result.map(&:label))
        assert_equal(["fake.rb"], result.map { _1.label_details.description })
      end
    end
  end

  def test_completion_for_constant_paths
    source = +<<~RUBY
      class Bar
      end

      class Foo::Bar
      end

      module Foo
        B
      end

      Foo::B
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 7, character: 3 },
        })

        result = server.pop_response.response
        assert_equal(["Foo::Bar", "Bar"], result.map(&:label))
        assert_equal(["Bar", "::Bar"], result.map(&:filter_text))
        assert_equal(["Bar", "::Bar"], result.map { |completion| completion.text_edit.new_text })

        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 10, character: 6 },
        })

        result = server.pop_response.response
        assert_equal(["Foo::Bar"], result.map(&:label))
        assert_equal(["Foo::Bar"], result.map(&:filter_text))
        assert_equal(["Foo::Bar"], result.map { |completion| completion.text_edit.new_text })
      end
    end
  end

  def test_completion_conflicting_constants
    source = +<<~RUBY
      module Foo
        class Qux; end

        module Bar
          class Qux; end

          Q
        end

        Q
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 6, character: 5 },
        })

        result = server.pop_response.response
        assert_equal(["Foo::Bar::Qux", "Foo::Qux"], result.map(&:label))
        assert_equal(["Qux", "Foo::Qux"], result.map(&:filter_text))
        assert_equal(["Qux", "Foo::Qux"], result.map { |completion| completion.text_edit.new_text })
      end
    end
  end

  def test_completion_for_top_level_constants_inside_nesting
    source = +<<~RUBY
      class Bar
      end

      class Foo::Bar
      end

      module Foo
        ::B
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 7, character: 5 },
        })

        result = server.pop_response.response
        assert_equal(["Bar"], result.map(&:label))
        assert_equal(["::Bar"], result.map(&:filter_text))
        assert_equal(["::Bar"], result.map { |completion| completion.text_edit.new_text })
      end
    end
  end

  def test_completion_private_constants_inside_the_same_namespace
    source = +<<~RUBY
      class A
        CONST = 1
        private_constant(:CONST)

        C
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 3, character: 4 },
        })

        result = server.pop_response.response
        assert_equal(["CONST"], result.map { |completion| completion.text_edit.new_text })
      end
    end
  end

  def test_completion_private_constants_from_different_namespace
    source = +<<~RUBY
      class A
        CONST = 1
        private_constant(:CONST)
      end

      A::C
    RUBY

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 4, character: 5 },
        })

        result = server.pop_response.response
        assert_empty(result)
      end
    end
  end

  def test_completion_for_aliased_constants
    source = +<<~RUBY
      module A
        module B
          CONST = 1
        end
      end

      module Other
        ALIAS_NAME = A

        ALIAS_NAME::B::C
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 9, character: 18 },
        })

        result = server.pop_response.response
        assert_equal(["ALIAS_NAME::B::CONST"], result.map(&:label))
        assert_equal(["ALIAS_NAME::B::CONST"], result.map(&:filter_text))
        assert_equal(["ALIAS_NAME::B::CONST"], result.map { |completion| completion.text_edit.new_text })
      end
    end
  end

  def test_completion_for_aliased_complex_constants
    source = +<<~RUBY
      module A
        module B
          CONST = 1
        end
      end

      module Other
        ALIAS_NAME = A
      end

      FINAL_ALIAS = Other
      FINAL_ALIAS::ALIAS_NAME::B::C
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 11, character: 29 },
        })

        result = server.pop_response.response
        assert_equal(["FINAL_ALIAS::ALIAS_NAME::B::CONST"], result.map(&:label))
        assert_equal(["FINAL_ALIAS::ALIAS_NAME::B::CONST"], result.map(&:filter_text))
        assert_equal(["FINAL_ALIAS::ALIAS_NAME::B::CONST"], result.map { |completion| completion.text_edit.new_text })
      end
    end
  end

  def test_completion_uses_shortest_possible_name_for_filter_text
    source = +<<~RUBY
      module A
        module B
          class Foo
          end

          F
          A::B::F
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 5, character: 5 },
        })

        result = server.pop_response.response
        assert_equal(["A::B::Foo"], result.map(&:label))
        assert_equal(["Foo"], result.map(&:filter_text))
        assert_equal(["Foo"], result.map { |completion| completion.text_edit.new_text })

        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 6, character: 11 },
        })

        result = server.pop_response.response
        assert_equal(["A::B::Foo"], result.map(&:label))
        assert_equal(["A::B::Foo"], result.map(&:filter_text))
        assert_equal(["Foo"], result.map { |completion| completion.text_edit.new_text })
      end
    end
  end

  def test_completion_for_inherited_constants
    source = +<<~RUBY
      module Foo
        Bar = 1
      end

      class Baz
        include Foo

        # Not inherited: direct reference
        Foo::B

        # Inherited through include
        B
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 8, character: 8 },
      })

      result = server.pop_response.response
      assert_equal(["Foo::Bar"], result.map(&:label))

      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 11, character: 3 },
      })

      result = server.pop_response.response
      assert_equal(["Foo::Bar", "Baz"], result.map(&:label))
    end
  end

  def test_completion_for_inherited_constants_with_constant_path
    source = +<<~RUBY
      module Foo
        Bar = 1
      end

      class Baz
        include Foo
      end

      Baz::B
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 8, character: 6 },
      })

      result = server.pop_response

      item = result.response.first
      assert_equal("Baz::Bar", item.label)
      assert_equal("Baz::Bar", item.text_edit.new_text)
      assert_equal(
        { start: { line: 8, character: 0 }, end: { line: 8, character: 6 } },
        item.text_edit.range.to_hash.transform_values(&:to_hash),
      )
    end
  end

  def test_completion_for_inherited_constants_with_constant_path_but_no_name
    source = +<<~RUBY
      module Foo
        Bar = 1
      end

      class Baz
        include Foo
      end

      Baz::
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 8, character: 5 },
      })

      result = server.pop_response.response
      assert_equal(["Baz::Bar"], result.map(&:label))
      assert_equal(["Baz::Bar"], result.map { |completion| completion.text_edit.new_text })
    end
  end

  def test_completion_for_constants_inside_aliased_namespaces
    source = +<<~RUBY
      module First
        module Second
          class Foo
          end
        end
      end

      module Namespace
        Second = First::Second

        Second::
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 10, character: 10 },
      })

      result = server.pop_response.response
      assert_equal(["Second::Foo"], result.map(&:label))
      assert_equal(["Second::Foo"], result.map { |completion| completion.text_edit.new_text })
    end
  end

  def test_completion_for_methods_invoked_on_self
    source = +<<~RUBY
      class Foo
        def qux1(a, b); end
        def qux2(c, d); end

        def process
          q
        end
      end
    RUBY

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 5, character: 5 },
        })

        result = server.pop_response.response
        assert_equal(["qux2", "qux1"], result.map(&:label))
        assert_equal(["qux2", "qux1"], result.map(&:filter_text))
        assert_equal(["qux2", "qux1"], result.map { |completion| completion.text_edit.new_text })
        assert_equal(["fake.rb", "fake.rb"], result.map { _1.label_details.description })
      end
    end
  end

  def test_completion_for_methods_invoked_on_explicit_self
    source = +<<~RUBY
      class Foo
        def bar(a, b); end
        def baz(c, d); end

        def process
          self.b
        end
      end
    RUBY

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 5, character: 10 },
        })

        result = server.pop_response.response
        assert_equal(["baz", "bar"], result.map(&:label))
        assert_equal(["baz", "bar"], result.map(&:filter_text))
        assert_equal(["baz", "bar"], result.map { |completion| completion.text_edit.new_text })
        assert_equal([9, 9], result.map { |completion| completion.text_edit.range.start.character })
      end
    end
  end

  def test_completion_for_methods_named_with_uppercase_characters
    source = +<<~RUBY
      class Kernel
        def Array(a); end

        def process
          Array(
        end
      end
    RUBY

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 4, character: 10 },
        })

        result = server.pop_response.response
        assert_equal(["Array"], result.map(&:label))
        assert_equal(["Array"], result.map(&:filter_text))
        assert_equal(["Array"], result.map { |completion| completion.text_edit.new_text })
      end
    end
  end

  def test_completion_for_attributes
    source = +<<~RUBY
      class Foo
        attr_accessor :qux

        def bar
          q
        end
      end
    RUBY

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 4, character: 5 },
        })

        result = server.pop_response.response
        assert_equal(["qux", "qux="], result.map(&:label))
        assert_equal(["qux", "qux="], result.map(&:filter_text))
        assert_equal(["qux", "qux="], result.map { |completion| completion.text_edit.new_text })
      end
    end
  end

  def test_with_typed_false
    source = +<<~RUBY
      # typed: false
      class Foo
        def complete_me
        end

        def you
          comp
        end
      end
    RUBY

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 6, character: 8 },
        })

        result = server.pop_response.response
        assert_equal(["complete_me"], result.map(&:label))
      end
    end
  end

  def test_with_typed_true
    source = +<<~RUBY
      # typed: true
      class Foo
        def complete_me
        end

        def you
          comp
        end
      end
    RUBY

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 6, character: 8 },
        })

        result = server.pop_response.response
        assert_empty(result)
      end
    end
  end

  def test_completion_for_inherited_methods
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

          def do_it
            m
          end
        end
      end
    RUBY

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 13, character: 7 },
        })

        result = server.pop_response.response
        assert_equal(["module", "method2", "method1"], result.map(&:label))
      end
    end
  end

  def test_relative_completion_command
    prefix = "support/"
    source = <<~RUBY
      require_relative "#{prefix}"
    RUBY
    start_char = source.index('"') #: as !nil
    end_char = source.rindex('"') #: as !nil
    start_position = { line: 0, character: start_char + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server|
      with_file_structure(server) do |tmpdir|
        uri = URI("file://#{tmpdir}/foo/fake.rb")
        server.process_message({
          method: "textDocument/didOpen",
          params: {
            textDocument: {
              uri: uri,
              text: source,
              version: 1,
              languageId: "ruby",
            },
          },
        })

        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 0, character: end_char },
        })

        result = server.pop_response.response
        expected = [
          path_completion("support/bar", start_position, end_position),
          path_completion("support/baz", start_position, end_position),
          path_completion("support/quux", start_position, end_position),
        ]

        assert_equal(expected.to_json, result.to_json)
      end
    end
  end

  def test_relative_completion_call
    prefix = "../"
    source = <<~RUBY
      require_relative("#{prefix}")
    RUBY
    start_char = source.index('"') #: as !nil
    end_char = source.rindex('"') #: as !nil
    start_position = { line: 0, character: start_char + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server|
      with_file_structure(server) do |tmpdir|
        uri = URI("file://#{tmpdir}/foo/fake.rb")
        server.process_message({
          method: "textDocument/didOpen",
          params: {
            textDocument: {
              uri: uri,
              text: source,
              version: 1,
              languageId: "ruby",
            },
          },
        })

        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 0, character: end_char },
        })

        result = server.pop_response.response
        expected = [
          path_completion("../foo/bar", start_position, end_position),
          path_completion("../foo/baz", start_position, end_position),
          path_completion("../foo/quux", start_position, end_position),
          path_completion("../foo/support/bar", start_position, end_position),
          path_completion("../foo/support/baz", start_position, end_position),
          path_completion("../foo/support/quux", start_position, end_position),
        ]

        assert_equal(expected.to_json, result.to_json)
      end
    end
  end

  def test_relative_completion_command_call
    prefix = "./"
    source = <<~RUBY
      Kernel.require_relative "#{prefix}"
    RUBY
    start_char = source.index('"') #: as !nil
    end_char = source.rindex('"') #: as !nil
    start_position = { line: 0, character: start_char + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server|
      with_file_structure(server) do |tmpdir|
        uri = URI("file://#{tmpdir}/foo/support/fake.rb")
        server.process_message({
          method: "textDocument/didOpen",
          params: {
            textDocument: {
              uri: uri,
              text: source,
              version: 1,
              languageId: "ruby",
            },
          },
        })

        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 0, character: end_char },
        })

        result = server.pop_response.response
        expected = [
          path_completion("./bar", start_position, end_position),
          path_completion("./baz", start_position, end_position),
          path_completion("./quux", start_position, end_position),
        ]

        assert_equal(expected.to_json, result.to_json)
      end
    end
  end

  def test_relative_completion_command_call_without_leading_dot
    source = <<~RUBY
      Kernel.require_relative "b"
    RUBY
    start_char = source.index('"') #: as !nil
    end_char = source.rindex('"') #: as !nil
    start_position = { line: 0, character: start_char + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server|
      with_file_structure(server) do |tmpdir|
        uri = URI("file://#{tmpdir}/foo/quxx.rb")
        server.process_message({
          method: "textDocument/didOpen",
          params: {
            textDocument: {
              uri: uri,
              text: source,
              version: 1,
              languageId: "ruby",
            },
          },
        })

        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 0, character: end_char },
        })

        result = server.pop_response.response
        expected = [
          path_completion("bar", start_position, end_position),
          path_completion("baz", start_position, end_position),
          path_completion("support/bar", start_position, end_position),
          path_completion("support/baz", start_position, end_position),
        ]

        assert_equal(expected.to_json, result.to_json)
      end
    end
  end

  def test_relative_completion_with_partial_path
    prefix = "../suppo"
    source = <<~RUBY
      require_relative "#{prefix}"
    RUBY

    start_char = source.index('"') #: as !nil
    end_char = source.rindex('"') #: as !nil
    start_position = { line: 0, character: start_char + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server|
      with_file_structure(server) do |tmpdir|
        uri = URI("file://#{tmpdir}/foo/support/fake.rb")
        server.process_message({
          method: "textDocument/didOpen",
          params: {
            textDocument: {
              uri: uri,
              text: source,
              version: 1,
              languageId: "ruby",
            },
          },
        })

        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: { line: 0, character: end_char },
        })

        result = server.pop_response.response
        expected = [
          path_completion("../support/bar", start_position, end_position),
          path_completion("../support/baz", start_position, end_position),
          path_completion("../support/quux", start_position, end_position),
        ]

        assert_equal(expected.to_json, result.to_json)
      end
    end
  end

  def test_completion_addons
    source = <<~RUBY
      R
    RUBY

    begin
      create_completion_addon

      with_server(source) do |server, uri|
        server.process_message(
          id: 1,
          method: "textDocument/completion",
          params: { textDocument: { uri: uri }, position: { character: 1, line: 0 } },
        )
        response = server.pop_response.response

        assert_equal(1, response.size)
        assert_match("MyCompletion", response[0].label)
      end
    ensure
      RubyLsp::Addon.addon_classes.clear
    end
  end

  def test_completion_for_global_variables
    source = <<~RUBY
      $qar &&= 1
      $qaz += 1
      $qux ||= 1
      $quux, $qorge = 1
      $qoo = 1

      $q
      $LOAD
      $
    RUBY

    with_server(source) do |server, uri|
      index = server.instance_variable_get(:@global_state).index
      RubyIndexer::RBSIndexer.new(index).index_ruby_core

      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 6, character: 2 },
      })

      result = server.pop_response.response
      assert_equal(["$qoo", "$qorge", "$quux", "$qux", "$qaz", "$qar"], result.map(&:label))

      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 7, character: 5 },
      })

      result = server.pop_response.response
      assert_equal(["$LOAD_PATH", "$LOADED_FEATURES"], result.map(&:label))
      assert_equal(["global_variables.rbs", "global_variables.rbs"], result.map { _1.label_details.description })

      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 8, character: 1 },
      })

      result = server.pop_response.response
      assert_operator(result.size, :>, 40)
    end
  end

  def test_completion_for_global_variables_show_only_uniq_entries
    source = <<~RUBY
      $qar &&= 1
      $qar += 1
      $qar ||= 1
      $q
    RUBY

    with_server(source) do |server, uri|
      index = server.instance_variable_get(:@global_state).index
      RubyIndexer::RBSIndexer.new(index).index_ruby_core

      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 3, character: 2 },
      })

      result = server.pop_response.response
      assert_equal(["$qar"], result.map(&:label))
    end
  end

  def test_completion_for_class_variables
    source = <<~RUBY
      class Foo
        def set_variables
          @@foo = 1
          @@foobar = 2
        end

        def bar
          @
        end

        def baz
          @@ = 123
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 7, character: 5 },
      })

      result = server.pop_response.response
      assert_equal(["@@foo", "@@foobar"], result.map(&:label))
      assert_equal(["fake.rb", "fake.rb"], result.map { _1.label_details.description })
    end
  end

  def test_completion_for_class_variables_node
    source = <<~RUBY
      class Foo
        def set_variables
          @@foo = 1
          @@foobar = 2
        end

        def bar
          @@
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 7, character: 6 },
      })

      result = server.pop_response.response
      assert_equal(["@@foo", "@@foobar"], result.map(&:label))
    end
  end

  def test_completion_for_inherited_class_variables
    source = <<~RUBY
      module Foo
        def set_variable
          @@bar = 9
        end
      end

      class Parent
        def set_variable
          @@baz = 5
        end
      end

      class Child < Parent
        include Foo

        def do_something
          @
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 16, character: 5 },
      })

      result = server.pop_response.response
      assert_equal(["@@baz", "@@bar"], result.map(&:label))
    end
  end

  def test_completion_for_class_variables_show_only_unique_entries
    source = <<~RUBY
      class Foo
        def set_variables
          @@foo = 1
          @@foo = 2
        end

        def bar
          @
        end

        def baz
          @@ = 123
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 7, character: 5 },
      })

      result = server.pop_response.response
      assert_equal(["@@foo"], result.map(&:label))
    end
  end

  def test_completion_for_class_variables_in_different_context
    source = <<~RUBY
      class Foo
        @@a = 1

        class << self
          @@b = 2

          def foo
            @@c = 3
          end
        end

        def bar
          @
        end

        def baz
          @@ = 4
        end

        def self.foobar
          @@d = 5
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 12, character: 5 },
      })

      result = server.pop_response.response
      assert_equal(["@@d", "@@c", "@@b", "@@a"], result.map(&:label))
    end
  end

  def test_completion_for_instance_variables
    source = +<<~RUBY
      class Foo
        def initialize
          @foo = 1
          @foobar = 2
        end

        def bar
          @
        end

        def baz
          @ = 123
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 7, character: 5 },
      })
      result = server.pop_response.response
      assert_equal(["@foo", "@foobar"], result.map(&:label))

      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 11, character: 5 },
      })
      result = server.pop_response.response
      assert_equal(["@foo", "@foobar"], result.map(&:label))
      assert_equal(["fake.rb", "fake.rb"], result.map { _1.label_details.description })
    end
  end

  def test_completion_for_inherited_instance_variables
    source = +<<~RUBY
      module Foo
        def set_ivar
          @a = 9
          @b = 1
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
          @
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 17, character: 5 },
      })

      result = server.pop_response.response
      assert_equal(["@b", "@a"], result.map(&:label))
    end
  end

  def test_instance_variable_completion_shows_only_uniq_entries
    source = +<<~RUBY
      class Foo
        def initialize
          @foo = 1
        end

        def other_set_foo
          @foo = 2
        end

        def baz
          @
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 10, character: 5 },
      })
      result = server.pop_response.response
      assert_equal(["@foo"], result.map(&:label))
    end
  end

  def test_completion_for_singleton_methods
    source = +<<~RUBY
      class Foo
        def self.baz; end

        class << self
          def bar
            b
          end
        end
      end

      Foo.
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 10, character: 4 },
      })

      result = server.pop_response.response
      assert_equal(["bar", "baz"], result.map(&:label))

      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 5, character: 7 },
      })

      result = server.pop_response.response
      assert_equal(["begin", "break", "bar", "baz"], result.map(&:label))
    end
  end

  def test_completion_for_class_instance_variables
    source = +<<~RUBY
      class Foo
        @a = 1

        def self.baz
          @b = 2
        end

        class << self
          def bar
            @c = 3
          end

          def qux
            @
          end
        end

        def self.yeah
          @
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 13, character: 7 },
      })

      result = server.pop_response.response
      assert_equal(["@c", "@b", "@a"], result.map(&:label))

      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 18, character: 5 },
      })

      result = server.pop_response.response
      assert_equal(["@c", "@b", "@a"], result.map(&:label))
    end
  end

  def test_completion_for_aliased_methods
    source = +<<~RUBY
      class Parent
        def bar(a); end
      end

      class Child < Parent
        alias baz bar

        def do_something
          b
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 8, character: 5 },
      })
      result = server.pop_response.response
      assert_equal(["begin", "break", "baz", "bar"], result.map(&:label))
    end
  end

  def test_completion_for_locals
    source = +<<~RUBY
      class Child
        abc0 = 42

        def do_something(abc1, abc2, abc3)
          a

          [].each do |abc4, abc5|
            a
          end
        end

        a
      end

      abc = 12
      a
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 4, character: 5 },
      })

      result = server.pop_response.response
      assert_equal(["abc1", "abc2", "abc3", "alias", "and"], result.map(&:label))

      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 7, character: 7 },
      })

      result = server.pop_response.response
      assert_equal(["abc1", "abc2", "abc3", "abc4", "abc5", "alias", "and"], result.map(&:label))

      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 11, character: 3 },
      })

      result = server.pop_response.response
      assert_equal(["abc0", "alias", "and"], result.map(&:label))

      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 15, character: 1 },
      })

      result = server.pop_response.response
      assert_equal(["abc", "alias", "and"], result.map(&:label))
    end
  end

  def test_completion_for_locals_only_happens_when_there_is_no_receiver
    source = +<<~RUBY
      class Child
        def do_something
          abc = 123

          foo.a
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 4, character: 9 },
      })

      result = server.pop_response.response
      assert_empty(result.map(&:label))
    end
  end

  def test_self_method_completion_is_disabled_on_typed_true
    source = +<<~RUBY
      # typed: true
      class Foo
        def bar
          b
        end

        def baz; end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 3, character: 5 },
      })

      assert_empty(server.pop_response.response)
    end
  end

  def test_local_completion_is_disabled_on_typed_true
    source = +<<~RUBY
      # typed: true
      class Foo
        def bar
          abc = 123
          a
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 4, character: 5 },
      })

      assert_empty(server.pop_response.response)
    end
  end

  def test_keyword_completion_is_disabled_on_typed_true
    source = +<<~RUBY
      # typed: true
      class Foo
        def bar
          yie
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 3, character: 7 },
      })

      assert_empty(server.pop_response.response)
    end
  end

  def test_instance_variable_completion_is_disabled_on_typed_strict
    source = +<<~RUBY
      # typed: strict
      class Foo
        def initialize
          @hello = 123
        end

        def bar
          @
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 7, character: 5 },
      })

      assert_empty(server.pop_response.response)
    end
  end

  def test_provides_constant_completion_on_type_ignore
    source = +<<~RUBY
      # typed: ignore
      class Foo
      end

      F
    RUBY

    end_position = { line: 4, character: 1 }

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.process_message(id: 1, method: "textDocument/completion", params: {
          textDocument: { uri: uri },
          position: end_position,
        })
        result = server.pop_response.response
        assert_equal(["Foo"], result.map(&:label))
        assert_equal(["fake.rb"], result.map { _1.label_details.description })
      end
    end
  end

  def test_guessed_type_name_is_only_included_for_guessed_types
    source = +<<~RUBY
      [].e
    RUBY

    with_server(source) do |server, uri|
      index = server.instance_variable_get(:@global_state).index
      RubyIndexer::RBSIndexer.new(index).index_ruby_core

      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 0, character: 4 },
      })

      items = server.pop_response.response
      items.each do |item|
        refute(item.data[:guessed_type])
      end
    end
  end

  def test_completion_for_private_methods
    source = +<<~RUBY
      class Foo
        def bar
          b
        end

        private

        def baz
        end
      end

      foo = Foo.new
      foo.b
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 2, character: 5 },
      })

      result = server.pop_response.response
      assert_includes(result.map(&:label), "baz")

      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 12, character: 5 },
      })

      result = server.pop_response.response
      refute_includes(result.map(&:label), "baz")
    end
  end

  def test_completion_for_protected_methods
    source = +<<~RUBY
      class Foo
        def bar
          b
        end

        protected

        def baz
        end
      end

      foo = Foo.new
      foo.b
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 2, character: 5 },
      })

      result = server.pop_response.response
      assert_includes(result.map(&:label), "baz")

      server.process_message(id: 1, method: "textDocument/completion", params: {
        textDocument: { uri: uri },
        position: { line: 12, character: 5 },
      })

      result = server.pop_response.response
      refute_includes(result.map(&:label), "baz")
    end
  end

  private

  def with_file_structure(server, &block)
    Dir.mktmpdir("path_completion_test") do |tmpdir|
      $LOAD_PATH << tmpdir

      # Set up folder structure like this
      # <tmpdir>
      # |-- foo
      # |   |-- bar.rb
      # |   |-- baz.rb
      # |   |-- quux.rb
      # |   |-- support
      # |       |-- bar.rb
      # |       |-- baz.rb
      # |       |-- quux.rb
      FileUtils.mkdir_p(tmpdir + "/foo/support")
      FileUtils.touch([
        tmpdir + "/foo/bar.rb",
        tmpdir + "/foo/baz.rb",
        tmpdir + "/foo/quux.rb",
        tmpdir + "/foo/support/bar.rb",
        tmpdir + "/foo/support/baz.rb",
        tmpdir + "/foo/support/quux.rb",
      ])

      index = server.global_state.index
      uris = Dir.glob(File.join(tmpdir, "**", "*.rb")).map! do |path|
        URI::Generic.from_path(load_path_entry: tmpdir, path: path)
      end

      uris.each { |uri| index.index_file(uri) }
      block.call(tmpdir)
    ensure
      $LOAD_PATH.delete(tmpdir)
    end
  end

  def path_completion(path, start_position, end_position)
    LanguageServer::Protocol::Interface::CompletionItem.new(
      label: path,
      text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
        range: LanguageServer::Protocol::Interface::Range.new(
          start: start_position,
          end: end_position,
        ),
        new_text: path,
      ),
      kind: LanguageServer::Protocol::Constant::CompletionItemKind::FILE,
    )
  end

  def create_completion_addon
    Class.new(RubyLsp::Addon) do
      def create_completion_listener(response_builder, nesting, dispatcher, uri)
        klass = Class.new do
          include RubyLsp::Requests::Support::Common

          def initialize(response_builder, _, dispatcher, uri)
            @uri = uri
            @response_builder = response_builder
            dispatcher.register(self, :on_constant_read_node_enter)
          end

          def on_constant_read_node_enter(node)
            @response_builder << RubyLsp::Interface::CompletionItem.new(
              label: "MyCompletion",
              text_edit: RubyLsp::Interface::TextEdit.new(
                range: T.bind(self, RubyLsp::Requests::Support::Common).range_from_node(node),
                new_text: "MyCompletion",
              ),
              kind: RubyLsp::Constant::CompletionItemKind::CONSTANT,
            )
          end
        end

        T.unsafe(klass).new(response_builder, nesting, dispatcher, uri)
      end

      def activate(global_state, outgoing_queue); end

      def deactivate; end

      def name
        "Foo"
      end

      def version
        "0.1.0"
      end
    end
  end
end
