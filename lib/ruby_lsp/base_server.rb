# typed: strict
# frozen_string_literal: true

module RubyLsp
  class BaseServer
    extend T::Sig
    extend T::Helpers

    abstract!

    sig { params(test_mode: T::Boolean).void }
    def initialize(test_mode: false)
      @test_mode = T.let(test_mode, T::Boolean)
      @writer = T.let(Transport::Stdio::Writer.new, Transport::Stdio::Writer)
      @reader = T.let(Transport::Stdio::Reader.new, Transport::Stdio::Reader)
      @incoming_queue = T.let(Thread::Queue.new, Thread::Queue)
      @outgoing_queue = T.let(Thread::Queue.new, Thread::Queue)
      @cancelled_requests = T.let([], T::Array[Integer])
      @mutex = T.let(Mutex.new, Mutex)
      @worker = T.let(new_worker, Thread)
      @current_request_id = T.let(1, Integer)
      @store = T.let(Store.new, Store)
      @outgoing_dispatcher = T.let(
        Thread.new do
          unless test_mode
            while (message = @outgoing_queue.pop)
              @mutex.synchronize { @writer.write(message.to_hash) }
            end
          end
        end,
        Thread,
      )

      @global_state = T.let(GlobalState.new, GlobalState)
      Thread.main.priority = 1
    end

    sig { void }
    def start
      @reader.read do |message|
        method = message[:method]

        # We must parse the document under a mutex lock or else we might switch threads and accept text edits in the
        # source. Altering the source reference during parsing will put the parser in an invalid internal state, since
        # it started parsing with one source but then it changed in the middle. We don't want to do this for text
        # synchronization notifications
        @mutex.synchronize do
          uri = message.dig(:params, :textDocument, :uri)

          if uri
            begin
              parsed_uri = URI(uri)
              message[:params][:textDocument][:uri] = parsed_uri

              # We don't want to try to parse documents on text synchronization notifications
              unless method.start_with?("textDocument/did")
                document = @store.get(parsed_uri)

                # If the client supports request delegation and we're working with an ERB document and there was
                # something to parse, then we have to maintain the client updated about the virtual state of the host
                # language source
                if document.parse! && @global_state.supports_request_delegation && document.is_a?(ERBDocument)
                  send_message(
                    Notification.new(
                      method: "delegate/textDocument/virtualState",
                      params: {
                        textDocument: {
                          uri: uri,
                          text: document.host_language_source,
                        },
                      },
                    ),
                  )
                end
              end
            rescue Store::NonExistingDocumentError
              # If we receive a request for a file that no longer exists, we don't want to fail
            end
          end
        end

        # The following requests need to be executed in the main thread directly to avoid concurrency issues. Everything
        # else is pushed into the incoming queue
        case method
        when "initialize", "initialized", "textDocument/didOpen", "textDocument/didClose", "textDocument/didChange"
          process_message(message)
        when "shutdown"
          send_log_message("Shutting down Ruby LSP...")

          shutdown

          @mutex.synchronize do
            run_shutdown
            @writer.write(Result.new(id: message[:id], response: nil).to_hash)
          end
        when "exit"
          @mutex.synchronize do
            status = @incoming_queue.closed? ? 0 : 1
            send_log_message("Shutdown complete with status #{status}")
            exit(status)
          end
        else
          @incoming_queue << message
        end
      end
    end

    sig { void }
    def run_shutdown
      @incoming_queue.clear
      @outgoing_queue.clear
      @incoming_queue.close
      @outgoing_queue.close
      @cancelled_requests.clear

      @worker.join
      @outgoing_dispatcher.join
      @store.clear
    end

    # This method is only intended to be used in tests! Pops the latest response that would be sent to the client
    sig { returns(T.untyped) }
    def pop_response
      @outgoing_queue.pop
    end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def process_message(message); end

    sig { abstract.void }
    def shutdown; end

    sig { params(id: Integer, message: String, type: Integer).void }
    def fail_request_and_notify(id, message, type: Constant::MessageType::INFO)
      send_message(Error.new(id: id, code: Constant::ErrorCodes::REQUEST_FAILED, message: message))
      send_message(Notification.window_show_message(message, type: type))
    end

    sig { returns(Thread) }
    def new_worker
      Thread.new do
        while (message = T.let(@incoming_queue.pop, T.nilable(T::Hash[Symbol, T.untyped])))
          id = message[:id]

          # Check if the request was cancelled before trying to process it
          @mutex.synchronize do
            if id && @cancelled_requests.include?(id)
              send_message(Result.new(id: id, response: nil))
              @cancelled_requests.delete(id)
              next
            end
          end

          process_message(message)
        end
      end
    end

    sig { params(message: T.any(Result, Error, Notification, Request)).void }
    def send_message(message)
      # When we're shutting down the server, there's a small race condition between closing the thread queues and
      # finishing remaining requests. We may close the queue in the middle of processing a request, which will then fail
      # when trying to send a response back
      return if @outgoing_queue.closed?

      @outgoing_queue << message
      @current_request_id += 1 if message.is_a?(Request)
    end

    sig { params(id: Integer).void }
    def send_empty_response(id)
      send_message(Result.new(id: id, response: nil))
    end

    sig { params(message: String, type: Integer).void }
    def send_log_message(message, type: Constant::MessageType::LOG)
      send_message(Notification.window_log_message(message, type: Constant::MessageType::LOG))
    end
  end
end
