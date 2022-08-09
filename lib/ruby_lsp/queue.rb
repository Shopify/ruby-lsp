# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Queue
    class Cancelled < StandardError; end

    extend T::Sig

    class Job < T::Struct
      extend T::Sig

      const :action, T.proc.params(request: T::Hash[Symbol, T.untyped]).returns(T.untyped)
      const :request, T::Hash[Symbol, T.untyped]
      prop :cancelled, T::Boolean

      sig { void }
      def process
        action.call(request)
      end

      sig { void }
      def cancel
        self.cancelled = true
      end
    end

    sig { void }
    def initialize
      # The job queue is the actual list of requests we have to process
      @job_queue = T.let(Thread::Queue.new, Thread::Queue)
      # The jobs hash is just a way of keeping a handle to jobs based on the request ID, so we can cancel them
      @jobs = T.let({}, T::Hash[T.any(String, Integer), Job])
      # The current job is a handle to cancel jobs that are currently being processed
      @current_job = T.let(nil, T.nilable(Job))
      @mutex = T.let(Mutex.new, Mutex)
      @worker = T.let(
        Thread.new do
          loop do
            # Thread::Queue#pop is thread safe and will wait until an item is available
            job = @job_queue.pop
            # The only time when the job is nil is when the queue is closed and we can then terminate the thread
            break if job.nil?

            @mutex.synchronize do
              @jobs.delete(job.request[:id])
              @current_job = job
            end

            begin
              next if job.cancelled

              job.process # only the compute part should be cancelable - the IO after should be irrevoable
            rescue Cancelled
              next
            ensure
              @mutex.synchronize { @current_job = nil }
            end
          end
        end, Thread
      )
    end

    sig do
      params(
        request: T::Hash[Symbol, T.untyped],
        block: T.proc.params(request: T::Hash[Symbol, T.untyped]).returns(T.untyped)
      ).void
    end
    def push(request, &block)
      job = Job.new(request: request, action: block, cancelled: false)

      # Remember a handle to the job, so that we can cancel it
      @mutex.synchronize do
        @jobs[request[:id]] = job
      end

      @job_queue << job
    end

    sig { params(id: T.any(String, Integer)).void }
    def cancel(id)
      @mutex.synchronize do
        # Cancel the job if it's still in the queue
        @jobs[id]&.cancel

        # Cancel the job if we're in the middle of processing it
        if @current_job&.request&.dig(:id) == id
          @worker.raise(Cancelled)
        end
      end
    end

    sig { void }
    def shutdown
      # Close the queue so that we can no longer receive items
      @job_queue.close
      # Clear any remaining jobs so that the thread can terminate
      @job_queue.clear
      # Wait until the thread is finished
      @worker.join
    end
  end
end
