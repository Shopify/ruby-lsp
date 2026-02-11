# typed: true
# frozen_string_literal: true

require "test_helper"
require "coverage"
require "ruby_lsp/test_reporters/lsp_reporter"

module RubyLsp
  class LspReporterTest < Minitest::Test
    def setup
      @old_port = ENV["RUBY_LSP_REPORTER_PORT"]
      @old_test_runner = ENV["RUBY_LSP_TEST_RUNNER"]
    end

    def teardown
      ENV["RUBY_LSP_REPORTER_PORT"] = @old_port
      ENV["RUBY_LSP_TEST_RUNNER"] = @old_test_runner
    end

    def test_socket_connection_failure_fallbacks_to_stringio
      ENV["RUBY_LSP_REPORTER_PORT"] = "99999"

      reporter = LspReporter.new
      io = reporter.instance_variable_get(:@io)

      assert_kind_of(StringIO, io)
    end

    def test_socket_uses_ipv4_address_not_localhost
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1].to_s

      peer_info = nil #: [String, String]?
      thread = Thread.new do
        socket = server.accept
        peer_addr = socket.peeraddr
        # Store the values to assert outside the thread
        peer_info = [peer_addr[0], peer_addr[3]] #: [String, String]
        socket.close
      end

      ENV["RUBY_LSP_REPORTER_PORT"] = port
      reporter = LspReporter.new
      io = reporter.instance_variable_get(:@io)

      assert_kind_of(TCPSocket, io)

      thread.join(1)
      io.close
      server.close

      assert(peer_info, "Thread did not complete successfully")
      family, address = peer_info
      assert_equal("AF_INET", family)
      assert_equal("127.0.0.1", address)
    end

    def test_coverage_results_are_formatted_as_vscode_expects
      path = "/path/to/file.rb"
      Dir.expects(:pwd).returns("/path/to").at_least_once
      Coverage.expects(:result).returns({
        path => {
          lines: [1, 2, 3, nil],
          branches: {
            ["&.", 0, 2, 2, 3, 6] => { [:then, 1, 2, 2, 2, 6] => 0, [:else, 3, 3, 2, 3, 6] => 1 },
          },
        },
        "/unrelated/file.rb" => {
          lines: [1, 2, 3, nil],
          branches: {
            ["&.", 0, 2, 2, 3, 6] => { [:then, 1, 2, 2, 2, 6] => 0, [:else, 3, 3, 2, 3, 6] => 1 },
          },
        },
      })

      uri = URI::Generic.from_path(path: File.expand_path(path)).to_s

      assert_equal(
        {
          uri =>
            [
              { executed: 1, location: { line: 0, character: 0 }, branches: [] },
              { executed: 2, location: { line: 1, character: 0 }, branches: [] },
              {
                executed: 3,
                location: { line: 2, character: 0 },
                branches:
                [
                  {
                    groupingLine: 2,
                    executed: 0,
                    location:
                          { start: { line: 2, character: 2 }, end: { line: 2, character: 6 } },
                    label: "&. then",
                  },
                  {
                    groupingLine: 2,
                    executed: 1,
                    location:
                    { start: { line: 3, character: 2 }, end: { line: 3, character: 6 } },
                    label: "&. else",
                  },
                ],
              },
            ],
        },
        LspReporter.new.gather_coverage_results,
      )
    end

    def test_shutdown_does_nothing_in_coverage_mode
      ENV["RUBY_LSP_TEST_RUNNER"] = "coverage"
      reporter = LspReporter.new
      io = reporter.instance_variable_get(:@io)
      io.expects(:close).never
      reporter.shutdown
    ensure
      ENV.delete("RUBY_LSP_TEST_RUNNER")
    end
  end
end
