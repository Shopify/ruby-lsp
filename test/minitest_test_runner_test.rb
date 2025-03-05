# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class MinitestTestRunnerTest < Minitest::Test
    def test_minitest_output
      plugin_path = "lib/ruby_lsp/ruby_lsp_reporter_plugin.rb"
      env = { "RUBYOPT" => "-r./#{plugin_path}" }
      _stdin, stdout, _stderr, _wait_thr = T.unsafe(Open3).popen3(
        env,
        "bundle",
        "exec",
        "ruby",
        "-Itest",
        "test/fixtures/minitest_example.rb",
      )
      stdout.binmode
      stdout.sync = true

      actual = parse_output(stdout)

      uri = URI::Generic.from_path(path: "#{Dir.pwd}/test/fixtures/minitest_example.rb").to_s
      expected = [
        {
          "method" => "start",
          "params" => {
            "id" => "Sample#test_that_fails",
            "uri" => uri,
          },
        },
        {
          "method" => "fail",
          "params" => {
            "id" => "Sample#test_that_fails",
            "message" => "--- expected\n+++ actual\n@@ -1 +1 @@\n-1\n+2\n",
            "uri" => uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "Sample#test_that_is_pending",
            "uri" => uri,
          },
        },
        {
          "method" => "skip",
          "params" => {
            "id" => "Sample#test_that_is_pending",
            "message" => "pending test",
            "uri" => uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "Sample#test_that_passes",
            "uri" => uri,
          },
        },
        {
          "method" => "pass",
          "params" => {
            "id" => "Sample#test_that_passes",
            "uri" => uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "Sample#test_that_raises",
            "uri" => uri,
          },
        },
        {
          "method" => "error",
          "params" => {
            "id" => "Sample#test_that_raises",
            "message" => "RuntimeError: oops\n    test/fixtures/minitest_example.rb:23:in #{error_location}",
            "uri" => uri,
          },
        },
      ]
      assert_equal(8, actual.size)
      assert_equal(expected, actual)
    end

    private

    def parse_output(output)
      output.each_line("\r\n\r\n").map do |headers|
        content_length = headers[/Content-Length: (\d+)/i, 1]
        flunk("Error reading response") unless content_length
        data = output.read(Integer(content_length))
        JSON.parse(data)
      end
    end

    def error_location
      ruby_version = Gem::Version.new(RUBY_VERSION)

      # TODO: confirm when this behavior changed
      # Also note the difference in the initial character.
      if ruby_version >= Gem::Version.new("3.4")
        "'Sample#test_that_raises'"
      else
        "`test_that_raises'"
      end
    end
  end
end
