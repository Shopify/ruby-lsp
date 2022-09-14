# typed: true
# frozen_string_literal: true

require "test_helper"

class QueueTest < Minitest::Test
  def setup
    handlers = {
      # Jobs for this request will remain stuck waiting for something to be pushed to @blocking_signal
      "pop_blocking" => RubyLsp::Handler::RequestHandler.new(action: ->(_r) { @blocking_signal.pop }, parallel: true),
      # Jobs for this request run immediately pushing to @cancelled_run
      "cancelled_run" => RubyLsp::Handler::RequestHandler.new(
        action: ->(_r) { @cancelled_run.push(:run) },
        parallel: true
      ),
      # Jobs for this request run immediately and assert the right request was received
      "test" => RubyLsp::Handler::RequestHandler.new(
        action: ->(r) { assert_equal(@expected_request, r) },
        parallel: true
      ),
      "always_errors" => RubyLsp::Handler::RequestHandler.new(
        action: ->(_r) {
          @blocking_signal.push(:run)
          raise "foo"
        },
        parallel: true,
      ),
      "load_error" => RubyLsp::Handler::RequestHandler.new(
        action: ->(_r) { raise LoadError, "cannot require 'foo' -- no such file" }, parallel: true
      ),
    }

    @queue = RubyLsp::Queue.new(LanguageServer::Protocol::Transport::Stdio::Writer.new, handlers)
  end

  def test_push_adds_new_item_to_the_queue
    capture_subprocess_io do
      @expected_request = { id: 1, method: "test" }
      @queue.push(@expected_request)
      @queue.shutdown
    end
  end

  def test_before_processing
    capture_subprocess_io do
      @blocking_job_signal = Thread::Queue.new
      @cancelled_run = Thread::Queue.new

      @queue.push({ id: "blocking_job", method: "pop_blocking" })
      @queue.push({ id: "job_to_cancel", method: "cancelled_run" })

      @queue.cancel("job_to_cancel")
      @blocking_job_signal.push(:unblock)
      @queue.shutdown

      assert_empty(@cancelled_run)
    end
  end

  def test_cancel_after_processing
    capture_subprocess_io do
      @cancelled_run = Thread::Queue.new
      @blocking_job_signal = Thread::Queue.new

      @queue.push({ id: "job_to_cancel", method: "cancelled_run" })
      @queue.push({ id: "blocking_job", method: "pop_blocking" })

      assert_equal(:run, @cancelled_run.pop)

      @queue.cancel("job_to_cancel")
      @blocking_job_signal.push(:unblock)

      @queue.shutdown
    end
  end

  def test_execute_is_resilient_to_load_errors
    capture_subprocess_io do
      @queue.push({ id: "job_to_cancel", method: "load_error" })
      @queue.shutdown

      assert_equal(0, @queue.instance_variable_get(:@job_queue).length)
    end
  end

  def test_error_telemetry
    stdout, _ = capture_subprocess_io do
      @blocking_signal = Thread::Queue.new
      @queue.push({ id: 2, method: "always_errors" })
      assert_equal(:run, @blocking_signal.pop)

      @queue.shutdown

      assert_equal(0, @queue.instance_variable_get(:@job_queue).length)
    end

    # We get stdout back as a string with two entries. The request response and the telemetry notification. This splits
    # the two into separate JSONs
    stdout = stdout.sub(/Content-Length: (\d+)\R\R/i, "")
    stdout = stdout.sub(/Content-Length: (\d+)\R\R/i, "#SPLIT_HERE#")
    response, telemetry = stdout.split("#SPLIT_HERE#")

    # First response is the error result
    response = JSON.parse(response, symbolize_names: true)

    assert_equal(LanguageServer::Protocol::Constant::ErrorCodes::INTERNAL_ERROR, response.dig(:error, :code))
    assert_equal("#<RuntimeError: foo>", response.dig(:error, :message))

    # Second response is the error telemetry
    telemetry = JSON.parse(telemetry, symbolize_names: true)

    assert_equal("telemetry/event", telemetry[:method])
    assert_equal("RuntimeError", telemetry.dig(:params, :errorClass))
    assert_equal("foo", telemetry.dig(:params, :errorMessage))
    assert_match(%r{ruby-lsp/test/queue_test.rb:\d+}, telemetry.dig(:params, :backtrace))
  end
end
