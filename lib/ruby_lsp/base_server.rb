# typed: strict
# frozen_string_literal: true

module RubyLsp
  # @abstract
  class BaseServer
    #: (**untyped options) -> void
    def initialize(**options)
      @test_mode = options[:test_mode] #: bool?
      @setup_error = options[:setup_error] #: StandardError?
      @install_error = options[:install_error] #: StandardError?
      @writer = Transport::Stdio::Writer.new #: Transport::Stdio::Writer
      @reader = Transport::Stdio::Reader.new #: Transport::Stdio::Reader
      @incoming_queue = Thread::Queue.new #: Thread::Queue
      @outgoing_queue = Thread::Queue.new #: Thread::Queue
      @cancelled_requests = [] #: Array[Integer]
      @worker = new_worker #: Thread
      @current_request_id = 1 #: Integer
      @global_state = GlobalState.new #: GlobalState
      @store = Store.new(@global_state) #: Store
      @outgoing_dispatcher = Thread.new do
        unless @test_mode
          while (message = @outgoing_queue.pop)
            @global_state.synchronize { @writer.write(message.to_hash) }
          end
        end
      end #: Thread

      Thread.main.priority = 1

      # We read the initialize request in `exe/ruby-lsp` to be able to determine the workspace URI where Bundler should
      # be set up
      initialize_request = options[:initialize_request]
      process_message(initialize_request) if initialize_request
    end

    #: -> void
    def start
      @reader.read do |message|
        method = message[:method]

        # We must parse the document under a mutex lock or else we might switch threads and accept text edits in the
        # source. Altering the source reference during parsing will put the parser in an invalid internal state, since
        # it started parsing with one source but then it changed in the middle. We don't want to do this for text
        # synchronization notifications
        @global_state.synchronize do
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
                if document.parse! && @global_state.client_capabilities.supports_request_delegation &&
                    document.is_a?(ERBDocument)

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
        when "initialize", "initialized", "textDocument/didOpen", "textDocument/didClose", "textDocument/didChange",
          "rubyLsp/diagnoseState"
          process_message(message)
        when "shutdown"
          @global_state.synchronize do
            send_log_message("Shutting down Ruby LSP...")
            shutdown
            run_shutdown
            @writer.write(Result.new(id: message[:id], response: nil).to_hash)
          end
        when "exit"
          @global_state.synchronize { exit(@incoming_queue.closed? ? 0 : 1) }
        else
          @incoming_queue << message
        end
      end
    end

    #: -> void
    def run_shutdown
      @incoming_queue.clear
      @outgoing_queue.clear
      @incoming_queue.close
      @outgoing_queue.close
      @cancelled_requests.clear

      @worker.terminate
      @outgoing_dispatcher.terminate
      @store.clear
    end

    # This method is only intended to be used in tests! Pops the latest response that would be sent to the client
    #: -> untyped
    def pop_response
      @outgoing_queue.pop
    end

    # This method is only intended to be used in tests! Pushes a message to the incoming queue directly
    #: (Hash[Symbol, untyped] message) -> void
    def push_message(message)
      @incoming_queue << message
    end

    # @abstract
    #: (Hash[Symbol, untyped] message) -> void
    def process_message(message); end

    # @abstract
    #: -> void
    def shutdown; end

    #: (Integer id, String message, ?type: Integer) -> void
    def fail_request_and_notify(id, message, type: Constant::MessageType::INFO)
      send_message(Error.new(id: id, code: Constant::ErrorCodes::REQUEST_FAILED, message: message))
      send_message(Notification.window_show_message(message, type: type))
    end

    #: -> Thread
    def new_worker
      Thread.new do
        while (message = @incoming_queue.pop)
          id = message[:id]

          # Check if the request was cancelled before trying to process it
          @global_state.synchronize do
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

    #: ((Result | Error | Notification | Request) message) -> void
    def send_message(message)
      # When we're shutting down the server, there's a small race condition between closing the thread queues and
      # finishing remaining requests. We may close the queue in the middle of processing a request, which will then fail
      # when trying to send a response back
      return if @outgoing_queue.closed?

      @outgoing_queue << message
      @current_request_id += 1 if message.is_a?(Request)
    end

    #: (Integer id) -> void
    def send_empty_response(id)
      send_message(Result.new(id: id, response: nil))
    end

    #: (String message, ?type: Integer) -> void
    def send_log_message(message, type: Constant::MessageType::LOG)
      send_message(Notification.window_log_message(message, type: Constant::MessageType::LOG))
    end
  end
end
