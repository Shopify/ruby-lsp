# typed: strict
# frozen_string_literal: true

module RubyLsp
  Interface = LanguageServer::Protocol::Interface
  Constant = LanguageServer::Protocol::Constant
  Transport = LanguageServer::Protocol::Transport

  class Server
    extend T::Sig

    sig { void }
    def initialize
      @writer = T.let(Transport::Stdio::Writer.new, Transport::Stdio::Writer)
      @reader = T.let(Transport::Stdio::Reader.new, Transport::Stdio::Reader)
      @store = T.let(Store.new, Store)

      @processes = T.let({}, T::Hash[Symbol, T.untyped])
      @mutex = T.let(Mutex.new, Mutex)
      @worker = T.let(new_worker, Thread)
    end

    sig { void }
    def start
      warn("Starting Ruby LSP...")

      # Requests that have to be executed sequentially or in the main process are implemented here. All other requests
      # fall under the else branch which just pushes requests to the queue
      @reader.read do |request|
        case request[:method]
        when "initialize", "textDocument/didOpen", "textDocument/didClose", "textDocument/didChange"
          result = Executor.new(@store).execute(request)
          finalize_request(result, request)
        when "$/cancelRequest"
          # Kill the process if it still exists
          pid, request, _ = @mutex.synchronize { @processes.delete(request[:params][:id]) }

          # Handle request being processed
          Process.kill("INT", pid)

          # Remove request from open processes
          @processes.delete(request[:params][:id])

          # Return nil response for the request
          finalize_request(Result.new(response: nil, notifications: []), request)
        when "shutdown"
          warn("Shutting down Ruby LSP...")

          # Kill all processes of this group
          # Process.kill("INT", 0)
          @processes.each do |_, (pid, _, _)|
            Process.kill("INT", pid)
          end

          Thread.kill(@worker)
          @store.clear

          finalize_request(Result.new(response: nil, notifications: []), request)
        when "exit"
          # We return zero if shutdown has already been received or one otherwise as per the recommendation in the spec
          # https://microsoft.github.io/language-server-protocol/specification/#exit
          status = @store.empty? ? 0 : 1
          exit(status)
        else
          # Create reader/writer for communication with process
          process_reader, process_writer = IO.pipe

          # Fork process and store the pid to check when the process is finished / close when
          # the LSP recieves a shutdown request
          pid = fork do
            # Close reader as there is no main process -> sub process communication
            process_reader.close

            # Process request with new executor
            result = T.let(Executor.new(@store).execute(request), Executor)

            # Marshal result and pass back to main process with writer pipe
            Marshal.dump(result, process_writer)
          end

          # Close writer as there is no main process -> sub process communication
          process_writer.close

          # Store the process, the request that instigated it, and the reader to get back the result
          @mutex.synchronize { @processes[request[:id]] = [pid, request, process_reader] }
        end
      end
    end

    private

    # Finalize a Queue::Result. All IO operations should happen here to avoid any issues with cancelling requests
    sig { params(result: Result, request: T::Hash[Symbol, T.untyped]).void }
    def finalize_request(result, request)
      error = result.error
      response = result.response

      # If the response include any notifications, go through them and publish each one
      result.notifications.each { |n| @writer.write(method: n.message, params: n.params) }

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

      request_time = result.request_time
      if request_time
        @writer.write(method: "telemetry/event", params: telemetry_params(request, request_time, error))
      end
    end

    sig { returns(Thread) }
    def new_worker
      Thread.new do
        loop do
          @mutex.synchronize do
            # Iterate over the processes to check if they've finished, finalizing the request on result
            @processes.each do |id, (pid, request, reader)|
              # Check the process id without hanging
              # TODO: Handle, might raise if there are no child processes
              next unless Process.waitpid(pid, Process::WNOHANG)


              # Check the exit status and raise if non-zero
              # if $?.exitstatus != 0; end

              # Read result from reader
              # TODO: Handle, reader being empty
              result = T.cast(Marshal.load(reader.read), Result)

              # Finalize response for the request
              finalize_request(result, request)

              # Remove process from list
              @processes.delete(pid)
            end
          end
          sleep(1)
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
