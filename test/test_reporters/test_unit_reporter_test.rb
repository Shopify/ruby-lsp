# typed: true
# frozen_string_literal: true

require "test_helper"
require "socket"

module RubyLsp
  class TestUnitReporterTest < Minitest::Test
    def test_test_runner_output
      reporter_path = File.expand_path(File.join("lib", "ruby_lsp", "test_reporters", "test_unit_reporter.rb"))
      test_path = File.join(Dir.pwd, "test", "fixtures", "test_unit_example.rb")
      uri = URI::Generic.from_path(path: test_path).to_s

      server = TCPServer.new("localhost", 0)
      port = server.addr[1].to_s
      events = []
      socket = nil #: Socket?

      receiver = Thread.new do
        socket = server.accept
        socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)

        loop do
          headers = socket.gets("\r\n\r\n")
          break unless headers

          content_length = headers[/Content-Length: (\d+)/i, 1].to_i
          raw_message = socket.read(content_length)

          event = JSON.parse(raw_message)
          events << event

          break if event["method"] == "finish"
        end
      end

      _stdin, stdout, _stderr, wait_thr = Open3 #: as untyped
        .popen3(
          {
            "RUBYOPT" => "-rbundler/setup -r#{reporter_path}",
            "RUBY_LSP_TEST_RUNNER" => "run",
            "RUBY_LSP_REPORTER_PORT" => port,
          },
          "bundle",
          "exec",
          "ruby",
          "-Itest",
          test_path,
          chdir: Bundler.root.to_s,
        )

      wait_thr.join
      receiver.join
      socket&.close

      expected = [
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_fails",
            "uri" => uri,
            "line" => 11,
          },
        },
        {
          "method" => "fail",
          "params" => {
            "id" => "SampleTest#test_that_fails",
            "message" => "<1> expected but was\n<2>.",
            "uri" => uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_is_pending",
            "uri" => uri,
            "line" => 15,
          },
        },
        {
          "method" => "skip",
          "params" => {
            "id" => "SampleTest#test_that_is_pending",
            "uri" => uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_passes",
            "uri" => uri,
            "line" => 6,
          },
        },
        {
          "method" => "pass",
          "params" => {
            "id" => "SampleTest#test_that_passes",
            "uri" => uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_raises",
            "uri" => uri,
            "line" => 19,
          },
        },
        {
          "method" => "error",
          "params" => {
            "id" => "SampleTest#test_that_raises",
            "message" => "RuntimeError: oops",
            "uri" => uri,
          },
        },
        {
          "method" => "finish",
          "params" => {},
        },
      ]
      assert_equal(expected, events)
      refute_empty(stdout.read)
    end
  end
end
