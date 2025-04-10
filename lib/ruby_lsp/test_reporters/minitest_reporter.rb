# typed: strict
# frozen_string_literal: true

begin
  require "minitest"
rescue LoadError
  return
end

require_relative "lsp_reporter"
require "ruby_indexer/lib/ruby_indexer/uri"

module RubyLsp
  class MinitestReporter < Minitest::AbstractReporter
    class << self
      #: (Hash[untyped, untyped]) -> void
      def minitest_plugin_init(_options)
        Minitest.reporter.reporters << MinitestReporter.new
      end
    end

    #: (singleton(Minitest::Test) test_class, String method_name) -> void
    def prerecord(test_class, method_name)
      uri = uri_from_test_class(test_class, method_name)
      return unless uri

      LspReporter.instance.start_test(id: "#{test_class.name}##{method_name}", uri: uri)
    end

    #: (Minitest::Result result) -> void
    def record(result)
      id = "#{result.klass}##{result.name}"
      uri = uri_from_result(result)

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

    private

    #: (Minitest::Result result) -> URI::Generic
    def uri_from_result(result)
      file = result.source_location[0]
      absolute_path = File.expand_path(file, Dir.pwd)
      URI::Generic.from_path(path: absolute_path)
    end

    #: (singleton(Minitest::Test) test_class, String method_name) -> URI::Generic?
    def uri_from_test_class(test_class, method_name)
      file, _line = test_class.instance_method(method_name).source_location
      return unless file

      return if file.start_with?("(eval at ") # test is dynamically defined

      absolute_path = File.expand_path(file, Dir.pwd)
      URI::Generic.from_path(path: absolute_path)
    end
  end
end

Minitest.extensions << RubyLsp::MinitestReporter
