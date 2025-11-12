# typed: strict
# frozen_string_literal: true

require "English"
require "json"
require "socket"
require "singleton"
require "tmpdir"
require_relative "../../ruby_indexer/lib/ruby_indexer/uri"

module RubyLsp
  class LspReporter
    include Singleton

    # https://code.visualstudio.com/api/references/vscode-api#Position
    #: type position = { line: Integer, character: Integer }

    # https://code.visualstudio.com/api/references/vscode-api#Range
    #: type range = { start: position, end: position }

    # https://code.visualstudio.com/api/references/vscode-api#BranchCoverage
    #: type branch_coverage = { executed: Integer, label: String, location: range }

    # https://code.visualstudio.com/api/references/vscode-api#StatementCoverage
    #: type statement_coverage = { executed: Integer, location: position, branches: Array[branch_coverage] }

    #: -> void
    def initialize
      dir_path = File.join(Dir.tmpdir, "ruby-lsp")
      FileUtils.mkdir_p(dir_path)

      port_db_path = File.join(dir_path, "test_reporter_port_db.json")
      port = ENV["RUBY_LSP_REPORTER_PORT"]

      @io = begin
        # The environment variable is only used for tests. The extension always writes to the temporary file
        if port
          socket(port)
        elsif File.exist?(port_db_path)
          db = JSON.load_file(port_db_path)
          socket(db[Dir.pwd])
        else
          # For tests that don't spawn the TCP server
          require "stringio"
          StringIO.new
        end
      rescue
        require "stringio"
        StringIO.new
      end #: IO | StringIO

      @invoked_shutdown = false #: bool
    end

    #: -> void
    def shutdown
      # When running in coverage mode, we don't want to inform the extension that we finished immediately after running
      # tests. We only do it after we finish processing coverage results, by invoking `internal_shutdown`
      return if ENV["RUBY_LSP_TEST_RUNNER"] == "coverage"

      internal_shutdown
    end

    # This method is intended to be used by the RubyLsp::LspReporter class itself only. If you're writing a custom test
    # reporter, use `shutdown` instead
    #: -> void
    def internal_shutdown
      @invoked_shutdown = true

      send_message("finish")
      @io.close
    end

    #: (id: String, uri: URI::Generic, ?line: Integer?) -> void
    def start_test(id:, uri:, line: nil)
      send_message("start", id: id, uri: uri.to_s, line: line)
    end

    #: (id: String, uri: URI::Generic) -> void
    def record_pass(id:, uri:)
      send_message("pass", id: id, uri: uri.to_s)
    end

    #: (id: String, message: String, uri: URI::Generic) -> void
    def record_fail(id:, message:, uri:)
      send_message("fail", id: id, message: message, uri: uri.to_s)
    end

    #: (id: String, uri: URI::Generic) -> void
    def record_skip(id:, uri:)
      send_message("skip", id: id, uri: uri.to_s)
    end

    #: (id: String, message: String?, uri: URI::Generic) -> void
    def record_error(id:, message:, uri:)
      send_message("error", id: id, message: message, uri: uri.to_s)
    end

    #: (Method | UnboundMethod) -> [URI::Generic, Integer?]?
    def uri_and_line_for(method_object)
      file_path, line = method_object.source_location
      return unless file_path
      return if file_path.start_with?("(eval at ")

      uri = URI::Generic.from_path(path: File.expand_path(file_path))
      zero_based_line = line ? line - 1 : nil
      [uri, zero_based_line]
    end

    # Gather the results returned by Coverage.result and format like the VS Code test explorer expects
    #
    # Coverage result format:
    #
    # Lines are reported in order as an array where each number is the number of times it was executed. For example,
    # the following says that line 0 was executed 1 time and line 1 executed 3 times: [1, 3].
    # Nil values represent lines for which coverage is not available, like empty lines, comments or keywords like
    # `else`
    #
    # Branches are a hash containing the name of the branch and the location where it is found in tuples with the
    # following elements: [NAME, ID, START_LINE, START_COLUMN, END_LINE, END_COLUMN] as the keys and the value is the
    # number of times it was executed
    #
    # Methods are a similar hash [ClassName, :method_name, START_LINE, START_COLUMN, END_LINE, END_COLUMN] => NUMBER
    # OF EXECUTIONS
    #
    # Example:
    # {
    #   "file_path" => {
    #     "lines" => [1, 2, 3, nil],
    #     "branches" => {
    #       ["&.", 0, 6, 21, 6, 65] => { [:then, 1, 6, 21, 6, 65] => 0, [:else, 5, 7, 0, 7, 87] => 1 }
    #     },
    #     "methods" => {
    #       ["Foo", :bar, 6, 21, 6, 65] => 0
    #     }
    # }
    #: -> Hash[String, statement_coverage]
    def gather_coverage_results
      # Ignore coverage results inside dependencies
      bundle_path = Bundler.bundle_path.to_s

      result = Coverage.result.reject do |file_path, _coverage_info|
        file_path.start_with?(bundle_path) || !file_path.start_with?(Dir.pwd)
      end

      result.to_h do |file_path, coverage_info|
        # Format the branch coverage information as VS Code expects it and then group it based on the start line of
        # the conditional that causes the branching. We need to match each line coverage data with the branches that
        # spawn from that line
        branch_by_line = coverage_info[:branches]
          .flat_map do |branch, data|
            branch_name, _branch_id, branch_start_line, _branch_start_col, _branch_end_line, _branch_end_col = branch

            data.map do |then_or_else, execution_count|
              name, _id, start_line, start_column, end_line, end_column = then_or_else

              {
                groupingLine: branch_start_line,
                executed: execution_count,
                location: {
                  start: { line: start_line, character: start_column },
                  end: { line: end_line, character: end_column },
                },
                label: "#{branch_name} #{name}",
              }
            end
          end
          .group_by { |branch| branch[:groupingLine] }

        # Format the line coverage information, gathering any branch coverage data associated with that line
        data = coverage_info[:lines].filter_map.with_index do |execution_count, line_index|
          next if execution_count.nil?

          {
            executed: execution_count,
            location: { line: line_index, character: 0 },
            branches: branch_by_line[line_index] || [],
          }
        end

        # The expected format is URI => { executed: number_of_times_executed, location: { ... }, branches: [ ... ] }
        [URI::Generic.from_path(path: File.expand_path(file_path)).to_s, data]
      end
    end

    #: -> void
    def at_coverage_exit
      coverage_results = gather_coverage_results
      File.write(File.join(".ruby-lsp", "coverage_result.json"), coverage_results.to_json)
      internal_shutdown
    end

    #: -> void
    def at_exit
      internal_shutdown unless @invoked_shutdown
    end

    class << self
      #: -> bool
      def start_coverage?
        ENV["RUBY_LSP_TEST_RUNNER"] == "coverage"
      end

      #: -> bool
      def executed_under_test_runner?
        !!(ENV["RUBY_LSP_TEST_RUNNER"] && ENV["RUBY_LSP_ENV"] != "test")
      end
    end

    private

    #: (String) -> TCPSocket
    def socket(port)
      socket = TCPSocket.new("localhost", port)
      socket.binmode
      socket.sync = true
      socket
    end

    #: (String?, **untyped) -> void
    def send_message(method_name, **params)
      json_message = { method: method_name, params: params }.to_json
      @io.write("Content-Length: #{json_message.bytesize}\r\n\r\n#{json_message}")
    end
  end
end

if RubyLsp::LspReporter.start_coverage?
  # Auto start coverage when running tests under that profile. This avoids the user from having to configure coverage
  # manually for their project or adding extra dependencies
  require "coverage"
  Coverage.start(:all)
end

if RubyLsp::LspReporter.executed_under_test_runner?
  at_exit do
    # Regular finish events are registered per test reporter. However, if the test crashes during loading the files
    # (e.g.: a bad require), we need to ensure that the execution is finalized so that the extension is not left hanging
    RubyLsp::LspReporter.instance.at_exit if $ERROR_INFO
  end
end
