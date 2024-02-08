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

      # The messages queue includes requests and notifications to be sent to the client
      @message_queue = T.let(Thread::Queue.new, Thread::Queue)

      # The executor is responsible for executing requests
      @executor = T.let(Executor.new(@store, @message_queue), Executor)

      # Create a thread to watch the messages queue and send them to the client
      @message_dispatcher = T.let(
        Thread.new do
          current_request_id = 1

          loop do
            message = @message_queue.pop
            break if message.nil?

            @mutex.synchronize do
              case message
              when Notification
                @writer.write(method: message.message, params: message.params)
              when Request
                @writer.write(id: current_request_id, method: message.message, params: message.params)
                current_request_id += 1
              end
            end
          end
        end,
        Thread,
      )

      Thread.main.priority = 1
    end

    sig { void }
    def start
      $stderr.puts("Starting Ruby LSP v#{VERSION}...")

      # Requests that have to be executed sequentially or in the main process are implemented here. All other requests
      # fall under the else branch which just pushes requests to the queue
      @reader.read do |request|
        case request[:method]
        when "initialize", "initialized", "textDocument/didOpen", "textDocument/didClose", "textDocument/didChange"
          result = @executor.execute(request)
          finalize_request(result, request)
        when "$/cancelRequest"
          # Cancel the job if it's still in the queue
          @mutex.synchronize { @jobs[request[:params][:id]]&.cancel }
        when "$/setTrace"
          VOID
        when "shutdown"
          $stderr.puts("Shutting down Ruby LSP...")

          @message_queue.close
          # Close the queue so that we can no longer receive items
          @job_queue.close
          # Clear any remaining jobs so that the thread can terminate
          @job_queue.clear
          @jobs.clear
          # Wait until the thread is finished
          @worker.join
          @message_dispatcher.join
          @store.clear

          Addon.addons.each(&:deactivate)
          finalize_request(Result.new(response: nil), request)
        when "exit"
          # We return zero if shutdown has already been received or one otherwise as per the recommendation in the spec
          # https://microsoft.github.io/language-server-protocol/specification/#exit
          status = @store.empty? ? 0 : 1
          $stderr.puts("Shutdown complete with status #{status}")
          exit(status)
        else
          # Default case: push the request to the queue to be executed by the worker
          job = Job.new(request: request, cancelled: false)

          @mutex.synchronize do
            # Remember a handle to the job, so that we can cancel it
            @jobs[request[:id]] = job

            # We must parse the document under a mutex lock or else we might switch threads and accept text edits in the
            # source. Altering the source reference during parsing will put the parser in an invalid internal state,
            # since it started parsing with one source but then it changed in the middle
            uri = request.dig(:params, :textDocument, :uri)
            @store.get(URI(uri)).parse if uri
          end

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
            Result.new(response: nil)
          else
            @executor.execute(request)
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
              data: {
                errorClass: error.class.name,
                errorMessage: error.message,
                backtrace: error.backtrace&.map { |bt| bt.sub(/^#{Dir.home}/, "~") }&.join("\n"),
              },
            },
          )
        elsif response != VOID
          @writer.write(id: request[:id], result: response)
        end
      end
    end
  end
end
