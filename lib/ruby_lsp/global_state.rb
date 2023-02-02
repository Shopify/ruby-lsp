# typed: strict
# frozen_string_literal: true

module RubyLsp
  class GlobalState
    extend T::Sig

    sig { returns(Store) }
    attr_reader :store

    sig { returns(Mutex) }
    attr_reader :mutex

    sig { void }
    def initialize
      @store = T.let(Store.new, Store)
      @queue_request = T.let(Thread::Queue.new, Thread::Queue)
      @queue_response = T.let(Thread::Queue.new, Thread::Queue)

      @mutex = T.let(Mutex.new, Mutex)
      @jobs = T.let({}, T::Hash[T.any(String, Integer), Job])
    end

    sig { params(id: T.any(Integer, String)).void }
    def cancel_job(id)
      @mutex.synchronize { @jobs[id]&.cancel }
    end

    sig { params(request: T::Hash[Symbol, T.untyped]).void }
    def push_request(request)
      # Default case: push the request to the queue to be executed by the worker
      job = Job.new(request: request, cancelled: false)

      # Remember a handle to the job, so that we can cancel it
      @mutex.synchronize { @jobs[request[:id]] = job }
      @queue_request << job
    end

    sig { returns(T.nilable(Job)) }
    def pop_request
      @queue_request.pop
    end

    sig { params(result: Result).void }
    def push_response(result)
      @queue_response << result
    end

    sig { returns(Result) }
    def pop_response
      @queue_response.pop
    end

    sig { params(id: T.any(Integer, String)).void }
    def remove_job_handle(id)
      @mutex.synchronize { @jobs.delete(id) }
    end

    sig { void }
    def shutdown
      @queue_request.close
      @queue_request.clear

      @queue_response.close
      @queue_response.clear
    end
  end
end
