# typed: strict
# frozen_string_literal: true

module RubyLsp
  # rubocop:disable RubyLsp/UseLanguageServerAliases
  Interface = LanguageServer::Protocol::Interface
  Constant = LanguageServer::Protocol::Constant
  Transport = LanguageServer::Protocol::Transport
  # rubocop:enable RubyLsp/UseLanguageServerAliases

  class Server
    extend T::Sig

    sig { void }
    def initialize
      @writer = T.let(Transport::Stdio::Writer.new, Transport::Stdio::Writer)
      @reader = T.let(Transport::Stdio::Reader.new, Transport::Stdio::Reader)
      @store = T.let(Store.new, Store)

      # The job queue is the actual list of requests we have to process
      @job_queue = T.let(Thread::Queue.new, Thread::Queue)
      # The jobs hash is just a way of keeping a handle to jobs based on the request ID, so we can cancel them
      @jobs = T.let({}, T::Hash[T.any(String, Integer), Job])
      @mutex = T.let(Mutex.new, Mutex)
      @worker = T.let(new_worker, Thread)
      @current_request_id = T.let(1, Integer)

      Thread.main.priority = 1
    end

    sig { void }
    def start
      warn("Starting Ruby LSP...")

      # Requests that have to be executed sequentially or in the main process are implemented here. All other requests
      # fall under the else branch which just pushes requests to the queue
      @reader.read do |request|
        case request[:method]
        when "initialize", "initialized", "textDocument/didOpen", "textDocument/didClose", "textDocument/didChange",
              "textDocument/formatting", "textDocument/onTypeFormatting", "codeAction/resolve"
          result = Executor.new(@store).execute(request)
          finalize_request(result, request)
        when "$/cancelRequest"
          # Cancel the job if it's still in the queue
          @mutex.synchronize { @jobs[request[:params][:id]]&.cancel }
        when "shutdown"
          warn("Shutting down Ruby LSP...")

          # Close the queue so that we can no longer receive items
          @job_queue.close
          # Clear any remaining jobs so that the thread can terminate
          @job_queue.clear
          @jobs.clear
          # Wait until the thread is finished
          @worker.join
          @store.clear

          finalize_request(Result.new(response: nil, messages: []), request)
        when "exit"
          # We return zero if shutdown has already been received or one otherwise as per the recommendation in the spec
          # https://microsoft.github.io/language-server-protocol/specification/#exit
          status = @store.empty? ? 0 : 1
          warn("Shutdown complete with status #{status}")
          exit(status)
        else
          # Default case: push the request to the queue to be executed by the worker
          job = Job.new(request: request, cancelled: false)

          # Remember a handle to the job, so that we can cancel it
          @mutex.synchronize { @jobs[request[:id]] = job }
          @job_queue << job
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
            Result.new(response: nil, messages: [])
          else
            Executor.new(@store).execute(request)
          end

          finalize_request(result, request)
        end
      end
    end

    # Finalize a Queue::Result. All IO operations should happen here to avoid any issues with cancelling requests
    sig { params(result: Result, request: T::Hash[Symbol, T.untyped]).void }
    def finalize_request(result, request)
      @mutex.synchronize do
        error = result.error
        response = result.response

        if error
          @writer.write(
            id: request[:id],
            error: {
              code: Constant::ErrorCodes::INTERNAL_ERROR,
              message: error.inspect,
              data: request.to_json,
            },
          )
        elsif response != VOID
          @writer.write(id: request[:id], result: response)
        end

        # If the response include any messages, go through them and publish each one
        result.messages.each do |n|
          case n
          when Notification
            @writer.write(method: n.message, params: n.params)
          when Request
            @writer.write(id: @current_request_id, method: n.message, params: n.params)
            @current_request_id += 1
          end
        end

        request_time = result.request_time
        if request_time
          @writer.write(method: "telemetry/event", params: telemetry_params(request, request_time, error))
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

        log_params = request[:params]
        params[:params] = log_params.reject { |k, _| k == :textDocument }.to_json if log_params

        backtrace = error.backtrace
        params[:backtrace] = backtrace.map { |bt| bt.sub(/^#{Dir.home}/, "~") }.join("\n") if backtrace
      end

      params[:uri] = uri.sub(%r{.*://#{Dir.home}}, "~") if uri
      params
    end
  end
end
