# typed: strict
# frozen_string_literal: true

require "benchmark"

module RubyLsp
  class Queue
    extend T::Sig

    class Result < T::Struct
      const :response, T.untyped # rubocop:disable Sorbet/ForbidUntypedStructProps
      const :error, T.nilable(Exception)
      const :request_time, T.nilable(Float)
    end

    class Job < T::Struct
      extend T::Sig

      const :request, T::Hash[Symbol, T.untyped]
      prop :cancelled, T::Boolean

      sig { void }
      def cancel
        self.cancelled = true
      end
    end

    sig do
      params(
        writer: LanguageServer::Protocol::Transport::Stdio::Writer,
        handlers: T::Hash[String, Handler::RequestHandler],
      ).void
    end
    def initialize(writer, handlers)
      @writer = writer
      @handlers = handlers
      # The job queue is the actual list of requests we have to process
      @job_queue = T.let(Thread::Queue.new, Thread::Queue)
      # The jobs hash is just a way of keeping a handle to jobs based on the request ID, so we can cancel them
      @jobs = T.let({}, T::Hash[T.any(String, Integer), Job])
      @mutex = T.let(Mutex.new, Mutex)
      @worker = T.let(new_worker, Thread)

      Thread.main.priority = 1
    end

    sig { params(request: T::Hash[Symbol, T.untyped]).void }
    def push(request)
      job = Job.new(request: request, cancelled: false)

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

    # Executes a request and returns a Queue::Result. No IO should happen in this method, because it can be cancelled in
    # the middle with a raise
    sig { params(request: T::Hash[Symbol, T.untyped]).returns(Queue::Result) }
    def execute(request)
      response = T.let(nil, T.untyped)
      error = T.let(nil, T.nilable(Exception))

      request_time = Benchmark.realtime do
        response = T.must(@handlers[request[:method]]).action.call(request)
      rescue StandardError, LoadError => e
        error = e
      end

      Queue::Result.new(response: response, error: error, request_time: request_time)
    end

    # Finalize a Queue::Result. All IO operations should happen here to avoid any issues with cancelling requests
    sig do
      params(
        result: Result,
        request: T::Hash[Symbol, T.untyped],
      ).void
    end
    def finalize_request(result, request)
      @mutex.synchronize do
        error = result.error
        if error
          T.must(@handlers[request[:method]]).error_handler&.call(error, request)

          @writer.write(
            id: request[:id],
            error: {
              code: LanguageServer::Protocol::Constant::ErrorCodes::INTERNAL_ERROR,
              message: error.inspect,
              data: request.to_json,
            },
          )
        elsif result.response != Handler::VOID
          @writer.write(id: request[:id], result: result.response)
        end

        request_time = result.request_time
        if request_time
          @writer.write(method: "telemetry/event", params: telemetry_params(request, request_time, error))
        end
      end
    end

    private

    sig { returns(Thread) }
    def new_worker
      Thread.new do
        # Thread::Queue#pop is thread safe and will wait until an item is available
        loop do
          job = T.let(@job_queue.pop, T.nilable(Job))
          # The only time when the job is nil is when the queue is closed and we can then terminate the thread
          break if job.nil?

          request = job.request
          @mutex.synchronize { @jobs.delete(request[:id]) }

          result = if job.cancelled
            # We need to return nil to the client even if the request was cancelled
            Queue::Result.new(response: nil, error: nil, request_time: nil)
          else
            execute(request)
          end

          finalize_request(result, request)
        end
      end
    end

    sig do
      params(
        request: T::Hash[Symbol, T.untyped],
        request_time: Float,
        error: T.nilable(Exception),
      ).returns(T::Hash[Symbol, T.any(String, Float)])
    end
    def telemetry_params(request, request_time, error)
      uri = request.dig(:params, :textDocument, :uri)

      params = {
        request: request[:method],
        lspVersion: RubyLsp::VERSION,
        requestTime: request_time,
      }

      if error
        params[:errorClass] = error.class.name
        params[:errorMessage] = error.message

        log_params = request[:params]&.reject { |k, _| k == :textDocument }
        params[:params] = log_params.to_json if log_params&.any?

        backtrace = error.backtrace
        params[:backtrace] = backtrace.map { |bt| bt.sub(/^#{Dir.home}/, "~") }.join("\n") if backtrace
      end

      params[:uri] = uri.sub(%r{.*://#{Dir.home}}, "~") if uri
      params
    end
  end
end
