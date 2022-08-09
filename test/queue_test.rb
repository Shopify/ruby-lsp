# typed: true
# frozen_string_literal: true

require "test_helper"

class QueueTest < Minitest::Test
  def setup
    @queue = RubyLsp::Queue.new
  end

  def test_push_adds_new_item_to_the_queue
    expected_request = { id: 1, method: "test" }

    @queue.push(expected_request) do |request|
      assert_equal(expected_request, request)
    end

    @queue.shutdown
  end

  def test_before_processing
    blocking_job_signal = Thread::Queue.new
    cancelled_run = Thread::Queue.new

    @queue.push({ id: "blocking_job", method: "test" }) do
      # This job blocks until we cancel the second one
      blocking_job_signal.pop
    end

    @queue.push({ id: "job_to_cancel", method: "test" }) do
      cancelled_run.push(:run)
    end

    @queue.cancel("job_to_cancel")
    blocking_job_signal.push(:unblock)
    @queue.shutdown

    assert_empty(cancelled_run)
  end

  def test_cancel_while_processing
    running_job_signal = Thread::Queue.new
    running_job_response = Thread::Queue.new

    @queue.push({ id: "job_to_cancel", method: "test" }) do
      running_job_response.push(:started)
      # The job is sitting here when it gets cancelled
      running_job_signal.pop
      running_job_response.push(:finished)
    end

    assert_equal(:started, running_job_response.pop)
    @queue.cancel("job_to_cancel")
    running_job_signal.push(:unblock)

    @queue.shutdown

    assert_empty(running_job_response)
  end

  def test_after_processing
    cancelled_run = Thread::Queue.new
    blocking_job_signal = Thread::Queue.new

    @queue.push({ id: "job_to_cancel", method: "test" }) do
      # This job runs straight away
      cancelled_run.push(:run)
    end

    @queue.push({ id: "blocking_job", method: "test" }) do
      # This job sits here until we're about to shutdown
      blocking_job_signal.pop
    end

    assert_equal(:run, cancelled_run.pop)

    @queue.cancel("job_to_cancel")
    blocking_job_signal.push(:unblock)

    @queue.shutdown
  end
end
