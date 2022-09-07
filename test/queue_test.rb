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
      # Jobs for this request start, pause waiting for @running_job_signal and never push :finished because they are
      # cancelled first
      "cancelled_in_the_middle" => RubyLsp::Handler::RequestHandler.new(
        action: ->(_r) {
          @running_job_response.push(:started)
          # The job is sitting here when it gets cancelled
          @running_job_signal.pop
          @running_job_response.push(:finished)
        },
        parallel: true
      ),
      "always_errors" => RubyLsp::Handler::RequestHandler.new(action: ->(_r) { raise "foo" }, parallel: true),
      "with_error_handler" => RubyLsp::Handler::RequestHandler.new(
        action: ->(_r) { raise "foo" }, parallel: true
      ),
      "load_error" => RubyLsp::Handler::RequestHandler.new(
        action: ->(_r) { raise LoadError, "cannot require 'foo' -- no such file" }, parallel: true
      ),
    }

    handlers["with_error_handler"].on_error do
      @running_job_response.push(:started)
      # The job is sitting here when it gets cancelled
      @blocking_job_signal.pop
      @running_job_response.push(:finished)
    end

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
      @cancelled_run = Thread::Queue.new
      @blocking_job_signal = Thread::Queue.new

      @queue.push({ id: "job_to_cancel", method: "load_error" })
      @queue.shutdown

      assert_equal(0, @queue.instance_variable_get(:@job_queue).length)
    end
  end
end
