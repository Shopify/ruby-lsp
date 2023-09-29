# typed: true
# frozen_string_literal: true

require "test_helper"

class CompletionTest < Minitest::Test
  def setup
    @message_queue = Thread::Queue.new
    @uri = URI("file:///fake.rb")
    @store = RubyLsp::Store.new
    @executor = RubyLsp::Executor.new(@store, @message_queue)
    stub_no_typechecker
  end

  def teardown
    T.must(@message_queue).close
  end

  def test_completion_command
    prefix = "foo/"

    document = RubyLsp::Document.new(source: <<~RUBY, version: 1, uri: @uri)
      require "#{prefix}"
    RUBY

    end_char = T.must(document.source.rindex('"'))
    start_position = {
      line: 0,
      character: T.must(document.source.index('"')),
    }
    end_position = {
      line: 0,
      character: end_char + 1,
    }

    result = with_file_structure do
      @store.set(uri: @uri, source: document.source, version: 1)
      run_request(
        method: "textDocument/completion",
        params: { textDocument: { uri: @uri.to_s }, position: { line: 0, character: end_char } },
      )
    end

    expected = [
      path_completion("foo/bar", prefix, start_position, end_position),
      path_completion("foo/baz", prefix, start_position, end_position),
      path_completion("foo/quux", prefix, start_position, end_position),
      path_completion("foo/support/bar", prefix, start_position, end_position),
      path_completion("foo/support/baz", prefix, start_position, end_position),
      path_completion("foo/support/quux", prefix, start_position, end_position),
    ]

    assert_equal(expected.to_json, result.to_json)
  end

  def test_completion_call
    prefix = "foo/"

    document = RubyLsp::Document.new(source: <<~RUBY, version: 1, uri: @uri)
      require("#{prefix}")
    RUBY

    end_char = T.must(document.source.rindex('"'))
    start_position = {
      line: 0,
      character: T.must(document.source.index('"')),
    }
    end_position = {
      line: 0,
      character: end_char + 1,
    }

    result = with_file_structure do
      @store.set(uri: @uri, source: document.source, version: 1)
      run_request(
        method: "textDocument/completion",
        params: { textDocument: { uri: @uri.to_s }, position: { line: 0, character: end_char } },
      )
    end

    expected = [
      path_completion("foo/bar", prefix, start_position, end_position),
      path_completion("foo/baz", prefix, start_position, end_position),
      path_completion("foo/quux", prefix, start_position, end_position),
      path_completion("foo/support/bar", prefix, start_position, end_position),
      path_completion("foo/support/baz", prefix, start_position, end_position),
      path_completion("foo/support/quux", prefix, start_position, end_position),
    ]

    assert_equal(expected.to_json, result.to_json)
  end

  def test_completion_command_call
    prefix = "foo/"

    document = RubyLsp::Document.new(source: <<~RUBY, version: 1, uri: @uri)
      Kernel.require "#{prefix}"
    RUBY

    end_char = T.must(document.source.rindex('"'))
    start_position = {
      line: 0,
      character: T.must(document.source.index('"')),
    }
    end_position = {
      line: 0,
      character: end_char + 1,
    }

    result = with_file_structure do
      @store.set(uri: @uri, source: document.source, version: 1)
      run_request(
        method: "textDocument/completion",
        params: { textDocument: { uri: @uri.to_s }, position: { line: 0, character: end_char } },
      )
    end

    expected = [
      path_completion("foo/bar", prefix, start_position, end_position),
      path_completion("foo/baz", prefix, start_position, end_position),
      path_completion("foo/quux", prefix, start_position, end_position),
      path_completion("foo/support/bar", prefix, start_position, end_position),
      path_completion("foo/support/baz", prefix, start_position, end_position),
      path_completion("foo/support/quux", prefix, start_position, end_position),
    ]

    assert_equal(expected.to_json, result.to_json)
  end

  def test_completion_with_partial_path
    prefix = "foo/suppo"

    document = RubyLsp::Document.new(source: <<~RUBY, version: 1, uri: @uri)
      require "#{prefix}"
    RUBY

    end_char = T.must(document.source.rindex('"'))
    start_position = {
      line: 0,
      character: T.must(document.source.index('"')),
    }
    end_position = {
      line: 0,
      character: end_char + 1,
    }

    result = with_file_structure do
      @store.set(uri: @uri, source: document.source, version: 1)
      run_request(
        method: "textDocument/completion",
        params: { textDocument: { uri: @uri.to_s }, position: { line: 0, character: end_char } },
      )
    end

    expected = [
      path_completion("foo/support/bar", prefix, start_position, end_position),
      path_completion("foo/support/baz", prefix, start_position, end_position),
      path_completion("foo/support/quux", prefix, start_position, end_position),
    ]

    assert_equal(expected.to_json, result.to_json)
  end

  def test_completion_does_not_fail_when_there_are_syntax_errors
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: @uri)
      require "ruby_lsp/requests/"

      def foo
    RUBY

    end_position = {
      line: 0,
      character: document.source.rindex('"'),
    }

    @store.set(uri: @uri, source: document.source, version: 1)
    run_request(
      method: "textDocument/completion",
      params: { textDocument: { uri: @uri.to_s }, position: end_position },
    )
  end

  def test_completion_is_not_triggered_if_argument_is_not_a_string
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: @uri)
      require foo
    RUBY

    end_position = {
      line: 0,
      character: document.source.rindex("o"),
    }

    @store.set(uri: @uri, source: document.source, version: 1)
    result = run_request(
      method: "textDocument/completion",
      params: { textDocument: { uri: @uri.to_s }, position: end_position },
    )
    assert_nil(result)
  end

  def test_completion_for_constants
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: @uri)
      class Foo
      end

      F
    RUBY

    end_position = { line: 3, character: 1 }
    @store.set(uri: @uri, source: document.source, version: 1)

    index = @executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, @uri.to_standardized_path), document.source)

    result = run_request(
      method: "textDocument/completion",
      params: { textDocument: { uri: @uri.to_s }, position: end_position },
    )
    assert_equal(["Foo"], result.map(&:label))
  end

  def test_completion_for_constant_paths
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: @uri)
      class Bar
      end

      class Foo::Bar
      end

      module Foo
        B
      end

      Foo::B
    RUBY

    @store.set(uri: @uri, source: document.source, version: 1)

    index = @executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, @uri.to_standardized_path), document.source)

    end_position = { line: 7, character: 3 }
    result = run_request(
      method: "textDocument/completion",
      params: { textDocument: { uri: @uri.to_s }, position: end_position },
    )
    assert_equal(["Foo::Bar", "Bar"], result.map(&:label))
    assert_equal(["Foo::Bar", "::Bar"], result.map(&:filter_text))
    assert_equal(["Bar", "::Bar"], result.map { |completion| completion.text_edit.new_text })

    end_position = { line: 10, character: 6 }
    result = run_request(
      method: "textDocument/completion",
      params: { textDocument: { uri: @uri.to_s }, position: end_position },
    )
    assert_equal(["Foo::Bar"], result.map(&:label))
    assert_equal(["Foo::Bar"], result.map(&:filter_text))
    assert_equal(["Foo::Bar"], result.map { |completion| completion.text_edit.new_text })
  end

  def test_completion_for_top_level_constants_inside_nesting
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: @uri)
      class Bar
      end

      class Foo::Bar
      end

      module Foo
        ::B
      end
    RUBY

    @store.set(uri: @uri, source: document.source, version: 1)

    index = @executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, @uri.to_standardized_path), document.source)

    end_position = { line: 7, character: 5 }
    result = run_request(
      method: "textDocument/completion",
      params: { textDocument: { uri: @uri.to_s }, position: end_position },
    )
    assert_equal(["Bar"], result.map(&:label))
    assert_equal(["::Bar"], result.map(&:filter_text))
    assert_equal(["::Bar"], result.map { |completion| completion.text_edit.new_text })
  end

  def test_completion_private_constants_inside_the_same_namespace
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: @uri)
      class A
        CONST = 1
        private_constant(:CONST)

        C
      end
    RUBY

    @store.set(uri: @uri, source: document.source, version: 1)

    index = @executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, @uri.to_standardized_path), document.source)

    end_position = { line: 3, character: 4 }
    result = run_request(
      method: "textDocument/completion",
      params: { textDocument: { uri: @uri.to_s }, position: end_position },
    )
    assert_equal(["CONST"], result.map { |completion| completion.text_edit.new_text })
  end

  def test_completion_private_constants_from_different_namespace
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: @uri)
      class A
        CONST = 1
        private_constant(:CONST)
      end

      A::C
    RUBY

    @store.set(uri: @uri, source: document.source, version: 1)

    index = @executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, @uri.to_standardized_path), document.source)

    end_position = { line: 4, character: 5 }
    result = run_request(
      method: "textDocument/completion",
      params: { textDocument: { uri: @uri.to_s }, position: end_position },
    )
    assert_empty(result)
  end

  private

  def run_request(method:, params: {})
    result = @executor.execute({ method: method, params: params })
    error = result.error
    raise error if error

    result.response
  end

  def with_file_structure(&block)
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

      index = @executor.instance_variable_get(:@index)
      indexables = Dir.glob(File.join(tmpdir, "**", "*.rb")).map! do |path|
        RubyIndexer::IndexablePath.new(tmpdir, path)
      end

      index.index_all(indexable_paths: indexables)

      return block.call
    ensure
      $LOAD_PATH.delete(tmpdir)
    end
  end

  def path_completion(path, prefix, start_position, end_position)
    LanguageServer::Protocol::Interface::CompletionItem.new(
      label: path,
      text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
        range: LanguageServer::Protocol::Interface::Range.new(
          start: start_position,
          end: end_position,
        ),
        new_text: path,
      ),
      kind: LanguageServer::Protocol::Constant::CompletionItemKind::REFERENCE,
    )
  end
end
