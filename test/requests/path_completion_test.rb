# typed: true
# frozen_string_literal: true

require "test_helper"

class PathCompletionTest < Minitest::Test
  def setup
    @message_queue = Thread::Queue.new
    @uri = URI("file:///fake.rb")
    @store = RubyLsp::Store.new
  end

  def teardown
    T.must(@message_queue).close
  end

  def test_completion_command
    prefix = "foo/"

    document = RubyLsp::Document.new(source: <<~RUBY, version: 1, uri: @uri)
      require "#{prefix}"
    RUBY

    start_position = {
      line: 0,
      character: T.must(document.source.index('"')) + 1,
    }
    end_position = {
      line: 0,
      character: document.source.rindex('"'),
    }

    result = with_file_structure do
      @store = RubyLsp::Store.new
      @store.set(uri: @uri, source: document.source, version: 1)
      run_request(
        method: "textDocument/completion",
        params: { textDocument: { uri: @uri.to_s }, position: end_position },
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

    start_position = {
      line: 0,
      character: T.must(document.source.index('"')) + 1,
    }
    end_position = {
      line: 0,
      character: document.source.rindex('"'),
    }

    result = with_file_structure do
      @store.set(uri: @uri, source: document.source, version: 1)
      run_request(
        method: "textDocument/completion",
        params: { textDocument: { uri: @uri.to_s }, position: end_position },
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

    start_position = {
      line: 0,
      character: T.must(document.source.index('"')) + 1,
    }
    end_position = {
      line: 0,
      character: document.source.rindex('"'),
    }

    result = with_file_structure do
      @store.set(uri: @uri, source: document.source, version: 1)
      run_request(
        method: "textDocument/completion",
        params: { textDocument: { uri: @uri.to_s }, position: end_position },
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

    start_position = {
      line: 0,
      character: T.must(document.source.index('"')) + 1,
    }
    end_position = {
      line: 0,
      character: document.source.rindex('"'),
    }

    result = with_file_structure do
      @store.set(uri: @uri, source: document.source, version: 1)
      run_request(
        method: "textDocument/completion",
        params: { textDocument: { uri: @uri.to_s }, position: end_position },
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

  private

  def run_request(method:, params: {})
    @executor = RubyLsp::Executor.new(@store, @message_queue)
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
