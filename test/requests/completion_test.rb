# typed: true
# frozen_string_literal: true

require "test_helper"

class CompletionTest < Minitest::Test
  def test_completion_command
    prefix = "foo/"
    source = <<~RUBY
      require "#{prefix}"
    RUBY
    end_char = T.must(source.rindex('"'))
    start_position = { line: 0, character: T.must(source.index('"')) + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.text_document_completion(id: 1, params: {
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
    end_char = T.must(source.rindex('"'))
    start_position = { line: 0, character: T.must(source.index('"')) + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.text_document_completion(id: 1, params: {
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
    end_char = T.must(source.rindex('"'))
    start_position = { line: 0, character: T.must(source.index('"')) + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.text_document_completion(id: 1, params: {
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
    end_char = T.must(source.rindex('"'))
    start_position = { line: 0, character: T.must(source.index('"')) + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.text_document_completion(id: 1, params: {
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
        server.text_document_completion(id: 1, params: {
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
        server.text_document_completion(id: 1, params: {
          textDocument: { uri: uri },
          position: end_position,
        })
        result = server.pop_response.response
        assert_empty(result)
      end
    end
  end

  def test_completion_for_constants
    stub_no_typechecker
    source = +<<~RUBY
      class Foo
      end

      F
    RUBY

    end_position = { line: 3, character: 1 }

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.text_document_completion(id: 1, params: {
          textDocument: { uri: uri },
          position: end_position,
        })
        result = server.pop_response.response
        assert_equal(["Foo"], result.map(&:label))
      end
    end
  end

  def test_completion_for_constant_paths
    stub_no_typechecker
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

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.text_document_completion(id: 1, params: {
          textDocument: { uri: uri },
          position: { line: 7, character: 3 },
        })

        result = server.pop_response.response
        assert_equal(["Foo::Bar", "Bar"], result.map(&:label))
        assert_equal(["Bar", "::Bar"], result.map(&:filter_text))
        assert_equal(["Bar", "::Bar"], result.map { |completion| completion.text_edit.new_text })

        server.text_document_completion(id: 1, params: {
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
    stub_no_typechecker
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

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.text_document_completion(id: 1, params: {
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
    stub_no_typechecker
    source = +<<~RUBY
      class Bar
      end

      class Foo::Bar
      end

      module Foo
        ::B
      end
    RUBY

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.text_document_completion(id: 1, params: {
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
    stub_no_typechecker
    source = +<<~RUBY
      class A
        CONST = 1
        private_constant(:CONST)

        C
      end
    RUBY

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.text_document_completion(id: 1, params: {
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
        server.text_document_completion(id: 1, params: {
          textDocument: { uri: uri },
          position: { line: 4, character: 5 },
        })

        result = server.pop_response.response
        assert_empty(result)
      end
    end
  end

  def test_completion_for_aliased_constants
    stub_no_typechecker
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

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.text_document_completion(id: 1, params: {
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
    stub_no_typechecker
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

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.text_document_completion(id: 1, params: {
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
    stub_no_typechecker
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

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.text_document_completion(id: 1, params: {
          textDocument: { uri: uri },
          position: { line: 5, character: 5 },
        })

        result = server.pop_response.response
        assert_equal(["A::B::Foo"], result.map(&:label))
        assert_equal(["Foo"], result.map(&:filter_text))
        assert_equal(["Foo"], result.map { |completion| completion.text_edit.new_text })

        server.text_document_completion(id: 1, params: {
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

  def test_completion_for_methods_invoked_on_self
    source = +<<~RUBY
      class Foo
        def bar(a, b); end
        def baz(c, d); end

        def process
          b
        end
      end
    RUBY

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.text_document_completion(id: 1, params: {
          textDocument: { uri: uri },
          position: { line: 5, character: 5 },
        })

        result = server.pop_response.response
        assert_equal(["bar", "baz"], result.map(&:label))
        assert_equal(["bar", "baz"], result.map(&:filter_text))
        assert_equal(["bar", "baz"], result.map { |completion| completion.text_edit.new_text })
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
        server.text_document_completion(id: 1, params: {
          textDocument: { uri: uri },
          position: { line: 5, character: 10 },
        })

        result = server.pop_response.response
        assert_equal(["bar", "baz"], result.map(&:label))
        assert_equal(["bar", "baz"], result.map(&:filter_text))
        assert_equal(["bar", "baz"], result.map { |completion| completion.text_edit.new_text })
        assert_equal(["(a, b)", "(c, d)"], result.map { |completion| completion.label_details.detail })
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
        server.text_document_completion(id: 1, params: {
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
        attr_accessor :bar

        def qux
          b
        end
      end
    RUBY

    with_server(source) do |server, uri|
      with_file_structure(server) do
        server.text_document_completion(id: 1, params: {
          textDocument: { uri: uri },
          position: { line: 4, character: 5 },
        })

        result = server.pop_response.response
        assert_equal(["bar", "bar="], result.map(&:label))
        assert_equal(["bar", "bar="], result.map(&:filter_text))
        assert_equal(["bar", "bar="], result.map { |completion| completion.text_edit.new_text })
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
        server.text_document_completion(id: 1, params: {
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
        server.text_document_completion(id: 1, params: {
          textDocument: { uri: uri },
          position: { line: 6, character: 8 },
        })

        result = server.pop_response.response
        assert_empty(result)
      end
    end
  end

  def test_relative_completion_command
    prefix = "support/"
    source = <<~RUBY
      require_relative "#{prefix}"
    RUBY
    end_char = T.must(source.rindex('"'))
    start_position = { line: 0, character: T.must(source.index('"')) + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server|
      with_file_structure(server) do |tmpdir|
        uri = URI("file://#{tmpdir}/foo/fake.rb")
        server.text_document_did_open({
          params: {
            textDocument: {
              uri: uri,
              text: source,
              version: 1,
            },
          },
        })

        server.text_document_completion(id: 1, params: {
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
    end_char = T.must(source.rindex('"'))
    start_position = { line: 0, character: T.must(source.index('"')) + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server|
      with_file_structure(server) do |tmpdir|
        uri = URI("file://#{tmpdir}/foo/fake.rb")
        server.text_document_did_open({
          params: {
            textDocument: {
              uri: uri,
              text: source,
              version: 1,
            },
          },
        })

        server.text_document_completion(id: 1, params: {
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
    end_char = T.must(source.rindex('"'))
    start_position = { line: 0, character: T.must(source.index('"')) + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server|
      with_file_structure(server) do |tmpdir|
        uri = URI("file://#{tmpdir}/foo/support/fake.rb")
        server.text_document_did_open({
          params: {
            textDocument: {
              uri: uri,
              text: source,
              version: 1,
            },
          },
        })

        server.text_document_completion(id: 1, params: {
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
    end_char = T.must(source.rindex('"'))
    start_position = { line: 0, character: T.must(source.index('"')) + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server|
      with_file_structure(server) do |tmpdir|
        uri = URI("file://#{tmpdir}/foo/quxx.rb")
        server.text_document_did_open({
          params: {
            textDocument: {
              uri: uri,
              text: source,
              version: 1,
            },
          },
        })

        server.text_document_completion(id: 1, params: {
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

    end_char = T.must(source.rindex('"'))
    start_position = { line: 0, character: T.must(source.index('"')) + 1 }
    end_position = { line: 0, character: end_char }

    with_server(source) do |server|
      with_file_structure(server) do |tmpdir|
        uri = URI("file://#{tmpdir}/foo/support/fake.rb")
        server.text_document_did_open({
          params: {
            textDocument: {
              uri: uri,
              text: source,
              version: 1,
            },
          },
        })

        server.text_document_completion(id: 1, params: {
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

      index = server.index
      indexables = Dir.glob(File.join(tmpdir, "**", "*.rb")).map! do |path|
        RubyIndexer::IndexablePath.new(tmpdir, path)
      end

      index.index_all(indexable_paths: indexables)

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
end
