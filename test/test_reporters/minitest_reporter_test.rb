# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class MinitestReporterTest < Minitest::Test
    def test_minitest_output
      plugin_path = File.expand_path("lib/ruby_lsp/test_reporters/minitest_reporter.rb")
      uri = URI::Generic.from_path(path: "#{Dir.pwd}/test/fixtures/minitest_example.rb").to_s

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
            "RUBYOPT" => "-rbundler/setup -r#{plugin_path}",
            "RUBY_LSP_TEST_RUNNER" => "run",
            "RUBY_LSP_REPORTER_PORT" => port,
          },
          "bundle",
          "exec",
          "ruby",
          "-Itest",
          "test/fixtures/minitest_example.rb",
        )

      receiver.join
      wait_thr.join
      socket&.close

      expected = [
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_fails",
            "uri" => uri,
            "line" => 14,
          },
        },
        {
          "method" => "fail",
          "params" => {
            "id" => "SampleTest#test_that_fails",
            "message" => "Expected: 1\n  Actual: 2",
            "uri" => uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_is_pending",
            "uri" => uri,
            "line" => 18,
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
            "line" => 9,
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
            "line" => 22,
          },
        },
        {
          "method" => "error",
          "params" => {
            "id" => "SampleTest#test_that_raises",
            "message" => "RuntimeError: oops\n    test/fixtures/minitest_example.rb:24:in #{error_location}",
            "uri" => uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_with_output",
            "uri" => uri,
            "line" => 26,
          },
        },
        {
          "method" => "pass",
          "params" => {
            "id" => "SampleTest#test_with_output",
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

    private

    def error_location
      ruby_version = Gem::Version.new(RUBY_VERSION)

      if ruby_version >= Gem::Version.new("3.4")
        "'SampleTest#test_that_raises'"
      else
        "`test_that_raises'"
      end
    end
  end
end
