# typed: strict
# frozen_string_literal: true

require "json"
require "socket"
require "singleton"

module RubyLsp
  class LspReporter
    include Singleton

    #: -> void
    def initialize
      port = ENV["RUBY_LSP_REPORTER_PORT"]
      @io = if port
        TCPSocket.new("localhost", port)
      else
        # For tests that don't spawn the TCP server
        require "stringio"
        StringIO.new
      end #: IO | StringIO
    end

    #: -> void
    def shutdown
      send_message("finish")
      @io.close
    end

    #: (id: String, uri: URI::Generic) -> void
    def start_test(id:, uri:)
      send_message("start", id: id, uri: uri.to_s)
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
    #: -> Hash[String, StatementCoverage]
    def gather_coverage_results
      # Ignore coverage results inside dependencies
      bundle_path = Bundler.bundle_path.to_s
      default_gems_path = File.dirname(RbConfig::CONFIG["rubylibdir"])

      result = Coverage.result.reject do |file_path, _coverage_info|
        file_path.start_with?(bundle_path, default_gems_path, "eval")
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

    private

    #: (method_name: String?, params: untyped) -> void
    def send_message(method_name, **params)
      json_message = { method: method_name, params: params }.to_json
      @io.write("Content-Length: #{json_message.bytesize}\r\n\r\n#{json_message}")
    end
  end
end

if ENV["RUBY_LSP_TEST_RUNNER"] == "coverage"
  # Auto start coverage when running tests under that profile. This avoids the user from having to configure coverage
  # manually for their project or adding extra dependencies
  require "coverage"
  Coverage.start(:all)

  at_exit do
    coverage_results = RubyLsp::LspReporter.instance.gather_coverage_results
    File.write(File.join(".ruby-lsp", "coverage_result.json"), coverage_results.to_json)
  end
end
