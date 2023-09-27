# typed: true
# frozen_string_literal: true

require "test_helper"

class ReferencesTest < Minitest::Test
  def setup
    stub_no_typechecker
    @message_queue = Thread::Queue.new
    @store = RubyLsp::Store.new
    @executor = RubyLsp::Executor.new(@store, @message_queue)
    @index = @executor.instance_variable_get(:@index)

    @index.index_single(RubyIndexer::IndexablePath.new(nil, File.expand_path("test/fixtures/class_and_reference.rb")))
  end

  def teardown
    RubyLsp::DependencyDetector.const_set(:HAS_TYPECHECKER, true)
    @message_queue.close
  end

  def test_returns_declaration_if_include_declaration_is_true
    @uri = URI("file:///fake.rb")
    @store.set(uri: @uri, source: "Foo", version: 1)

    response = run_request({
      textDocument: { uri: @uri.to_s },
      position: { line: 0, character: 0 },
      context: { includeDeclaration: true },
    })

    assert_equal(2, response.length)
    assert(response.all? { |r| r.uri.end_with?("class_and_reference.rb") })
  end

  def test_does_not_include_declaration_if_not_requested
    @uri = URI("file:///fake.rb")
    @store.set(uri: @uri, source: "Foo", version: 1)

    response = run_request({
      textDocument: { uri: @uri.to_s },
      position: { line: 0, character: 0 },
      context: { includeDeclaration: false },
    })

    assert_equal(1, response.length)
    assert(response.all? { |r| r.uri.end_with?("class_and_reference.rb") })
  end

  private

  def run_request(params)
    result = @executor.execute({ method: "textDocument/references", params: params })
    error = result.error
    raise error if error

    result.response
  end
end
