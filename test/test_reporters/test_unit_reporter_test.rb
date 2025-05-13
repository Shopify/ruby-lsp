# typed: true
# frozen_string_literal: true

require "test_helper"
require "socket"

module RubyLsp
  class TestUnitReporterTest < Minitest::Test
    def test_test_runner_output
      uri = URI::Generic.from_path(path: File.join(Dir.pwd, "test", "fixtures", "test_unit_example.rb"))
      uri_string = uri.to_s

      events = gather_events(uri)

      expected = [
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_fails",
            "uri" => uri_string,
            "line" => 11,
          },
        },
        {
          "method" => "fail",
          "params" => {
            "id" => "SampleTest#test_that_fails",
            "message" => "<1> expected but was\n<2>.",
            "uri" => uri_string,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_is_pending",
            "uri" => uri_string,
            "line" => 15,
          },
        },
        {
          "method" => "skip",
          "params" => {
            "id" => "SampleTest#test_that_is_pending",
            "uri" => uri_string,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_passes",
            "uri" => uri_string,
            "line" => 6,
          },
        },
        {
          "method" => "pass",
          "params" => {
            "id" => "SampleTest#test_that_passes",
            "uri" => uri_string,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_raises",
            "uri" => uri_string,
            "line" => 19,
          },
        },
        {
          "method" => "error",
          "params" => {
            "id" => "SampleTest#test_that_raises",
            "message" => "RuntimeError: oops",
            "uri" => uri_string,
          },
        },
        {
          "method" => "finish",
          "params" => {},
        },
      ]
      assert_equal(expected, events)
    end

    def test_crashing_example
      uri = URI::Generic.from_path(path: "#{Dir.pwd}/test/fixtures/test_unit_crash_example.rb")
      events = gather_events(uri, output: :stderr)

      expected = [{ "method" => "finish", "params" => {} }]
      assert_equal(expected, events)
    end

    private

    #: (URI::Generic, ?output: Symbol) -> Array[Hash[untyped, untyped]]
    def gather_events(uri, output: :stdout)
      reporter_path = File.expand_path(File.join("lib", "ruby_lsp", "test_reporters", "test_unit_reporter.rb"))

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

      _stdin, stdout, stderr, wait_thr = Open3.popen3(
        {
          "RUBYOPT" => "-rbundler/setup -r#{reporter_path}",
          "RUBY_LSP_TEST_RUNNER" => "run",
          "RUBY_LSP_REPORTER_PORT" => port,
          "RUBY_LSP_ENV" => "production",
        },
        "bundle",
        "exec",
        "ruby",
        "-Itest",
        uri.to_standardized_path, #: as !nil
        chdir: Bundler.root.to_s,
      )

      wait_thr.join
      receiver.join
      socket&.close

      io = output == :stdout ? stdout : stderr
      refute_empty(io.read)

      events
    end
  end
end
