# typed: true
# frozen_string_literal: true

require "test_helper"

class SignatureHelpTest < Minitest::Test
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

  def test_initial_request
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: @uri)
      class Foo
        def bar(a, b)
        end

        def baz
          bar()
        end
      end
    RUBY

    @store.set(uri: @uri, source: document.source, version: 1)

    index = @executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, @uri.to_standardized_path), document.source)

    result = run_request(
      method: "textDocument/signatureHelp",
      params: {
        textDocument: { uri: @uri.to_s },
        position: { line: 5, character: 7 },
        context: {
          triggerCharacter: "(",
          activeSignatureHelp: nil,
        },
      },
    )

    signature = result.signatures.first

    assert_equal("bar(a, b)", signature.label)
    assert_equal(0, result.active_parameter)
  end

  def test_help_after_comma
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: @uri)
      class Foo
        def bar(a, b)
        end

        def baz
          bar(a,)
        end
      end
    RUBY

    @store.set(uri: @uri, source: document.source, version: 1)

    index = @executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, @uri.to_standardized_path), document.source)

    result = run_request(
      method: "textDocument/signatureHelp",
      params: {
        textDocument: { uri: @uri.to_s },
        position: { line: 5, character: 9 },
        context: {
          triggerCharacter: ",",
        },
      },
    )

    signature = result.signatures.first

    assert_equal("bar(a, b)", signature.label)
    assert_equal(1, result.active_parameter)
  end

  def test_keyword_arguments
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: @uri)
      class Foo
        def bar(a:, b:)
        end

        def baz
          bar(b: 1,)
        end
      end
    RUBY

    @store.set(uri: @uri, source: document.source, version: 1)

    index = @executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, @uri.to_standardized_path), document.source)

    result = run_request(
      method: "textDocument/signatureHelp",
      params: {
        textDocument: { uri: @uri.to_s },
        position: { line: 5, character: 12 },
        context: {
          triggerCharacter: ",",
          activeSignatureHelp: nil,
        },
      },
    )

    signature = result.signatures.first

    assert_equal("bar(a:, b:)", signature.label)
    assert_equal(1, result.active_parameter)
  end

  def test_skipped_arguments
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: @uri)
      class Foo
        def bar(a, b = 123, c:, d:)
        end

        def baz
          bar(a, c: 1,)
        end
      end
    RUBY

    @store.set(uri: @uri, source: document.source, version: 1)

    index = @executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, @uri.to_standardized_path), document.source)

    result = run_request(
      method: "textDocument/signatureHelp",
      params: {
        textDocument: { uri: @uri.to_s },
        position: { line: 5, character: 15 },
        context: {
          triggerCharacter: ",",
          activeSignatureHelp: nil,
        },
      },
    )

    signature = result.signatures.first

    assert_equal("bar(a, b, c:, d:)", signature.label)
    assert_equal(2, result.active_parameter)
  end

  def test_help_for_splats
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: @uri)
      class Foo
        def bar(*a)
        end

        def baz
          bar(a, b, c, d, e)
        end
      end
    RUBY

    @store.set(uri: @uri, source: document.source, version: 1)

    index = @executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, @uri.to_standardized_path), document.source)

    result = run_request(
      method: "textDocument/signatureHelp",
      params: {
        textDocument: { uri: @uri.to_s },
        position: { line: 5, character: 20 },
        context: {},
      },
    )

    signature = result.signatures.first

    assert_equal("bar(*a)", signature.label)
    assert_equal(0, result.active_parameter)
  end

  def test_help_for_blocks
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: @uri)
      class Foo
        def bar(a, &block)
        end

        def baz
          bar(a,)
        end
      end
    RUBY

    @store.set(uri: @uri, source: document.source, version: 1)

    index = @executor.instance_variable_get(:@index)
    index.index_single(RubyIndexer::IndexablePath.new(nil, @uri.to_standardized_path), document.source)

    result = run_request(
      method: "textDocument/signatureHelp",
      params: {
        textDocument: { uri: @uri.to_s },
        position: { line: 5, character: 9 },
        context: {},
      },
    )

    signature = result.signatures.first

    assert_equal("bar(a, &block)", signature.label)
    assert_equal(1, result.active_parameter)
  end

  private

  def run_request(method:, params: {})
    result = @executor.execute({ method: method, params: params })
    error = result.error
    raise error if error

    result.response
  end
end
