# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Addon
    class ProcessClient
      class InitializationError < StandardError; end
      class IncompleteMessageError < StandardError; end
      class EmptyMessageError < StandardError; end

      MAX_RETRIES = 5

      extend T::Sig
      extend T::Generic

      abstract!

      sig { returns(Addon) }
      attr_reader :addon

      sig { returns(IO) }
      attr_reader :stdin

      sig { returns(IO) }
      attr_reader :stdout

      sig { returns(IO) }
      attr_reader :stderr

      sig { returns(Process::Waiter) }
      attr_reader :wait_thread

      sig { params(addon: Addon, command: String).void }
      def initialize(addon, command)
        @addon = T.let(addon, Addon)
        @mutex = T.let(Mutex.new, Mutex)
        # Spring needs a Process session ID. It uses this ID to "attach" itself to the parent process, so that when the
        # parent ends, the spring process ends as well. If this is not set, Spring will throw an error while trying to
        # set its own session ID
        begin
          Process.setpgrp
          Process.setsid
        rescue Errno::EPERM
          # If we can't set the session ID, continue
        rescue NotImplementedError
          # setpgrp() may be unimplemented on some platform
          # https://github.com/Shopify/ruby-lsp-rails/issues/348
        end

        stdin, stdout, stderr, wait_thread = Bundler.with_original_env do
          Open3.popen3(command)
        end

        @stdin = T.let(stdin, IO)
        @stdout = T.let(stdout, IO)
        @stderr = T.let(stderr, IO)
        @wait_thread = T.let(wait_thread, Process::Waiter)

        # for Windows compatibility
        @stdin.binmode
        @stdout.binmode
        @stderr.binmode

        log_output("booting server")
        count = 0

        begin
          count += 1
          handle_initialize_response(T.must(read_response))
        rescue EmptyMessageError
          log_output("is retrying initialize (#{count})")
          retry if count < MAX_RETRIES
        end

        log_output("finished booting server")

        register_exit_handler
      rescue Errno::EPIPE, IncompleteMessageError
        raise InitializationError, stderr.read
      end

      sig { void }
      def shutdown
        log_output("shutting down server")
        send_message("shutdown")
        sleep(0.5) # give the server a bit of time to shutdown
        [stdin, stdout, stderr].each(&:close)
      rescue IOError
        # The server connection may have died
        force_kill
      end

      sig { returns(T::Boolean) }
      def stopped?
        [stdin, stdout, stderr].all?(&:closed?) && !wait_thread.alive?
      end

      sig { params(message: String).void }
      def log_output(message)
        $stderr.puts("#{@addon.name} - #{message}")
      end

      # Notifications are like messages, but one-way, with no response sent back.
      sig { params(request: String, params: T.nilable(T::Hash[Symbol, T.untyped])).void }
      def send_notification(request, params = nil) = send_message(request, params)

      private

      sig do
        params(
          request: String,
          params: T.nilable(T::Hash[Symbol, T.untyped]),
        ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
      end
      def make_request(request, params = nil)
        send_message(request, params)
        read_response
      end

      sig { overridable.params(request: String, params: T.nilable(T::Hash[Symbol, T.untyped])).void }
      def send_message(request, params = nil)
        message = { method: request }
        message[:params] = params if params
        json = message.to_json

        @mutex.synchronize do
          @stdin.write("Content-Length: #{json.length}\r\n\r\n", json)
        end
      rescue Errno::EPIPE
        # The server connection died
      end

      sig { overridable.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def read_response
        raw_response = @mutex.synchronize do
          headers = @stdout.gets("\r\n\r\n")
          raise IncompleteMessageError unless headers

          content_length = headers[/Content-Length: (\d+)/i, 1].to_i
          raise EmptyMessageError if content_length.zero?

          @stdout.read(content_length)
        end

        response = JSON.parse(T.must(raw_response), symbolize_names: true)

        if response[:error]
          log_output("error: " + response[:error])
          return
        end

        response.fetch(:result)
      rescue Errno::EPIPE
        # The server connection died
        nil
      end

      sig { void }
      def force_kill
        # Windows does not support the `TERM` signal, so we're forced to use `KILL` here
        Process.kill(T.must(Signal.list["KILL"]), @wait_thread.pid)
      end

      sig { abstract.void }
      def register_exit_handler; end

      sig { abstract.params(response: T::Hash[Symbol, T.untyped]).void }
      def handle_initialize_response(response); end
    end
  end
end
