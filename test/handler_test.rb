# typed: true
# frozen_string_literal: true

require "test_helper"

class HandlerTest < Minitest::Test
  extend T::Sig

  def test_error_response_when_exceptions_raised
    handler = RubyLsp::Handler.new
    request = { jsonrpc: "2.0", id: 1, method: "foo", params: {} }

    handler.send(:on, "foo") do |_request|
      raise "foo"
    end

    response = make_request(handler, request)

    assert_equal(LanguageServer::Protocol::Constant::ErrorCodes::INTERNAL_ERROR, response.dig(:error, :code))
    assert_equal("#<RuntimeError: foo>", response.dig(:error, :message))
    assert_equal(request.to_json, response.dig(:error, :data))
  end

  sig { params(handler: RubyLsp::Handler, request: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def make_request(handler, request)
    mocked_stdout = mock_stdout do
      handler.send(:handle, request)
    end

    headers = mocked_stdout.gets("\r\n\r\n")
    raw_response = mocked_stdout.read(T.must(headers)[/Content-Length: (\d+)/i, 1].to_i)
    JSON.parse(T.must(raw_response), symbolize_names: true)
  end

  sig { params(block: T.proc.returns(T.untyped)).returns(Tempfile) }
  def mock_stdout(&block)
    mock_stdout = Tempfile.new

    original_stdout = $stdout.dup

    begin
      $stdout.reopen(mock_stdout)
      yield
    ensure
      $stdout.reopen(original_stdout)
    end

    # rewind to read from the start
    mock_stdout.rewind
    mock_stdout
  end
end
