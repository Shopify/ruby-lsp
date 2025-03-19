# typed: strict
# frozen_string_literal: true

require "json"
require "delegate"

$stdout.binmode
$stdout.sync = true
$stderr.binmode
$stderr.sync = true

module RubyLsp
  module TestReporter
    class << self
      #: (id: String, uri: URI::Generic) -> void
      def start_test(id:, uri:)
        params = {
          id: id,
          uri: uri.to_s,
        }
        send_message("start", params)
      end

      #: (id: String, uri: URI::Generic) -> void
      def record_pass(id:, uri:)
        params = {
          id: id,
          uri: uri.to_s,
        }
        send_message("pass", params)
      end

      #: (id: String, message: String, uri: URI::Generic) -> void
      def record_fail(id:, message:, uri:)
        params = {
          id: id,
          message: message,
          uri: uri.to_s,
        }
        send_message("fail", params)
      end

      #: (id: String, uri: URI::Generic) -> void
      def record_skip(id:, uri:)
        params = {
          id: id,
          uri: uri.to_s,
        }
        send_message("skip", params)
      end

      #: (id: String, message: String?, uri: URI::Generic) -> void
      def record_error(id:, message:, uri:)
        params = {
          id: id,
          message: message,
          uri: uri.to_s,
        }
        send_message("error", params)
      end

      #: (message: String) -> void
      def append_output(message:)
        params = {
          message: message,
        }
        send_message("append_output", params)
      end

      private

      #: (method_name: String?, params: Hash[String, untyped]) -> void
      def send_message(method_name, params)
        json_message = { method: method_name, params: params }.to_json
        ORIGINAL_STDOUT.write("Content-Length: #{json_message.bytesize}\r\n\r\n#{json_message}")
      end
    end

    ORIGINAL_STDOUT = $stdout #: IO

    class IOWrapper < SimpleDelegator
      #: (Object) -> void
      def puts(*args)
        args.each { |arg| log(convert_line_breaks(arg) + "\r\n") }
      end

      #: (Object) -> void
      def print(*args)
        args.each { |arg| log(convert_line_breaks(arg)) }
      end

      #: (Object) -> void
      def write(*args)
        args.each { |arg| log(convert_line_breaks(arg)) }
      end

      private

      #: (Object) -> String
      def convert_line_breaks(message)
        message.to_s.gsub("\n", "\r\n")
      end

      #: (String) -> void
      def log(message)
        TestReporter.append_output(message: message)
      end
    end
  end
end

# We wrap the default output stream so that we can capture anything written to stdout and emit it as part of
# the JSON event stream.
$> = RubyLsp::TestReporter::IOWrapper.new($stdout)
