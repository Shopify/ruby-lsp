# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class MinitestReporterTest < Minitest::Test
    def test_minitest_output
      uri = URI::Generic.from_path(path: "#{Dir.pwd}/test/fixtures/minitest_example.rb")
      string_uri = uri.to_s
      events = gather_events(uri)

      expected = [
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_fails",
            "uri" => string_uri,
            "line" => 14,
          },
        },
        {
          "method" => "fail",
          "params" => {
            "id" => "SampleTest#test_that_fails",
            "message" => "Expected: 1\n  Actual: 2",
            "uri" => string_uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_is_pending",
            "uri" => string_uri,
            "line" => 18,
          },
        },
        {
          "method" => "skip",
          "params" => {
            "id" => "SampleTest#test_that_is_pending",
            "uri" => string_uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_passes",
            "uri" => string_uri,
            "line" => 9,
          },
        },
        {
          "method" => "pass",
          "params" => {
            "id" => "SampleTest#test_that_passes",
            "uri" => string_uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_raises",
            "uri" => string_uri,
            "line" => 22,
          },
        },
        {
          "method" => "error",
          "params" => {
            "id" => "SampleTest#test_that_raises",
            "message" => "RuntimeError: oops\n    test/fixtures/minitest_example.rb:24:in #{error_location}",
            "uri" => string_uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_with_output",
            "uri" => string_uri,
            "line" => 26,
          },
        },
        {
          "method" => "pass",
          "params" => {
            "id" => "SampleTest#test_with_output",
            "uri" => string_uri,
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
      uri = URI::Generic.from_path(path: "#{Dir.pwd}/test/fixtures/minitest_crash_example.rb")
      events = gather_events(uri, output: :stderr)

      expected = [{ "method" => "finish", "params" => {} }]
      assert_equal(expected, events)
    end

    def test_minitest_spec_output
      uri = URI::Generic.from_path(path: "#{Dir.pwd}/test/fixtures/minitest_spec_example.rb")
      string_uri = uri.to_s
      events = gather_events(uri)

      expected = [
        {
          "method" => "start",
          "params" => {
            "id" => "First::Second::Third::MySpec::NestedSpec#test_0024_does something else",
            "uri" => string_uri,
            "line" => 24,
          },
        },
        {
          "method" => "pass",
          "params" => {
            "id" => "First::Second::Third::MySpec::NestedSpec#test_0024_does something else",
            "uri" => string_uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "First::Second::Third::MySpec#test_0012_anonymous",
            "uri" => string_uri,
            "line" => 12,
          },
        },
        {
          "method" => "pass",
          "params" => {
            "id" => "First::Second::Third::MySpec#test_0012_anonymous",
            "uri" => string_uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "First::Second::Third::MySpec::when something is true::and other thing is false#test_0018_does " \
              "what's expected",
            "uri" => string_uri,
            "line" => 18,
          },
        },
        {
          "method" => "pass",
          "params" => {
            "id" => "First::Second::Third::MySpec::when something is true::and other thing is false#test_0018_does " \
              "what's expected",
            "uri" => string_uri,
          },
        },
        { "method" => "finish", "params" => {} },
      ]

      assert_equal(
        expected.sort_by { |h| [h.dig("params", "id") || "", h["method"]] },
        events.sort_by { |h| [h.dig("params", "id") || "", h["method"]] },
      )
    end

    private

    #: (URI::Generic, ?output: Symbol) -> Array[Hash[untyped, untyped]]
    def gather_events(uri, output: :stdout)
      plugin_path = File.expand_path("lib/ruby_lsp/test_reporters/minitest_reporter.rb")

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
          "RUBYOPT" => "-rbundler/setup -r#{plugin_path}",
          "RUBY_LSP_TEST_RUNNER" => "run",
          "RUBY_LSP_REPORTER_PORT" => port,
          "RUBY_LSP_ENV" => "production",
        },
        "bundle",
        "exec",
        "ruby",
        "-Itest",
        uri.to_standardized_path, #: as !nil
      )

      receiver.join
      wait_thr.join
      socket&.close
      io = output == :stdout ? stdout : stderr
      refute_empty(io.read)
      events
    end

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
