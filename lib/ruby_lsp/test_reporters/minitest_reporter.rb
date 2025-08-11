# typed: strict
# frozen_string_literal: true

begin
  require "minitest"
rescue LoadError
  return
end

require_relative "lsp_reporter"

module RubyLsp
  # An override of the default progress reporter in Minitest to add color to the output
  class ProgressReporterWithColor < Minitest::ProgressReporter
    #: (Minitest::Result) -> void
    def record(result)
      color = if result.error?
        "\e[31m" # red
      elsif result.passed?
        "\e[32m" # green
      elsif result.skipped?
        "\e[33m" # yellow
      elsif result.failure
        "\e[31m" # red
      else
        "\e[0m" # no color
      end

      io.print("#{color}#{result.result_code}\e[0m") # Reset color after printing
    end
  end

  # This patch is here to prevent other gems from overriding or adding more Minitest reporters. Otherwise, they may
  # break the integration between the server and extension
  module PreventReporterOverridePatch
    @lsp_reporters = [] #: Array[Minitest::AbstractReporter]

    class << self
      #: Array[Minitest::AbstractReporter]
      attr_accessor :lsp_reporters
    end

    # Patch the writer to prevent replacing the entire array
    #: (untyped) -> void
    def reporters=(reporters)
      # Do nothing. We don't want other gems to override our reporter
    end

    # Patch the reader to prevent appending more reporters. This method always returns a temporary copy of the real
    # reporters so that if any gem mutates it, it continues to return the original reporters
    #: -> Array[untyped]
    def reporters
      PreventReporterOverridePatch.lsp_reporters.dup
    end
  end

  class MinitestReporter < Minitest::AbstractReporter
    class << self
      #: (Hash[untyped, untyped]) -> void
      def minitest_plugin_init(_options)
        # Remove the original progress reporter, so that we replace it with our own. We only do this if no other
        # reporters were included by the application itself to avoid double reporting
        reporters = Minitest.reporter.reporters

        if reporters.all? { |r| r.is_a?(Minitest::ProgressReporter) || r.is_a?(Minitest::SummaryReporter) }
          reporters.delete_if { |r| r.is_a?(Minitest::ProgressReporter) }
          reporters << ProgressReporterWithColor.new
        end

        # Add the JSON RPC reporter
        reporters << MinitestReporter.new
        PreventReporterOverridePatch.lsp_reporters = reporters
        Minitest.reporter.class.prepend(PreventReporterOverridePatch)
      end
    end

    #: (untyped, String) -> void
    def prerecord(test_class_or_wrapper, method_name)
      # In frameworks like Rails, they can control the Minitest execution by wrapping the test class
      # But they conform to responding to `name`, so we can use that as a guarantee
      # We are interested in the test class, not the wrapper
      name = test_class_or_wrapper.name

      klass = begin
        Object.const_get(name) # rubocop:disable Sorbet/ConstantsFromStrings
      rescue NameError
        # Handle Minitest specs that create classes with invalid constant names like "MySpec::when something is true"
        # If we can't resolve the constant, it means we were given the actual test class object, not the wrapper
        test_class_or_wrapper
      end

      uri, line = LspReporter.instance.uri_and_line_for(klass.instance_method(method_name))
      return unless uri

      id = "#{name}##{handle_spec_test_id(method_name, line)}"
      LspReporter.instance.start_test(id: id, uri: uri, line: line)
    end

    #: (Minitest::Result result) -> void
    def record(result)
      file_path, line = result.source_location
      return unless file_path

      zero_based_line = line ? line - 1 : nil
      name = handle_spec_test_id(result.name, zero_based_line)
      id = "#{result.klass}##{name}"

      uri = URI::Generic.from_path(path: File.expand_path(file_path))

      if result.error?
        message = result.failures.first.message
        LspReporter.instance.record_error(id: id, uri: uri, message: message)
      elsif result.passed?
        LspReporter.instance.record_pass(id: id, uri: uri)
      elsif result.skipped?
        LspReporter.instance.record_skip(id: id, uri: uri)
      elsif result.failure
        message = result.failure.message
        LspReporter.instance.record_fail(id: id, uri: uri, message: message)
      end
    end

    #: -> void
    def report
      LspReporter.instance.shutdown
    end

    #: (String, Integer?) -> String
    def handle_spec_test_id(method_name, line)
      method_name.gsub(/(?<=test_)\d{4}(?=_)/, format("%04d", line.to_s))
    end
  end
end

Minitest.extensions << RubyLsp::MinitestReporter

if RubyLsp::LspReporter.start_coverage?
  Minitest.after_run do
    RubyLsp::LspReporter.instance.at_coverage_exit
  end
elsif RubyLsp::LspReporter.executed_under_test_runner?
  Minitest.after_run do
    RubyLsp::LspReporter.instance.at_exit
  end
end
