# typed: strict
# frozen_string_literal: true

begin
  require "minitest"
rescue LoadError
  return
end

require_relative "test_reporter"
require "ruby_indexer/lib/ruby_indexer/uri"

module Minitest
  module Reporters
    class RubyLspReporter < ::Minitest::AbstractReporter
      class << self
        #: (Hash[untyped, untyped]) -> void
        def minitest_plugin_init(_options)
          Minitest.reporter.reporters << RubyLspReporter.new
        end
      end

      #: (singleton(Minitest::Test) test_class, String method_name) -> void
      def prerecord(test_class, method_name)
        uri = uri_from_test_class(test_class, method_name)
        return unless uri

        RubyLsp::TestReporter.instance.start_test(id: "#{test_class.name}##{method_name}", uri: uri)
      end

      #: (Minitest::Result result) -> void
      def record(result)
        id = "#{result.klass}##{result.name}"
        uri = uri_from_result(result)

        if result.error?
          message = result.failures.first.message
          RubyLsp::TestReporter.instance.record_error(id: id, uri: uri, message: message)
        elsif result.passed?
          RubyLsp::TestReporter.instance.record_pass(id: id, uri: uri)
        elsif result.skipped?
          RubyLsp::TestReporter.instance.record_skip(id: id, uri: uri)
        elsif result.failure
          message = result.failure.message
          RubyLsp::TestReporter.instance.record_fail(id: id, uri: uri, message: message)
        end
      end

      #: -> void
      def report
        RubyLsp::TestReporter.instance.shutdown
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
end

Minitest.extensions << Minitest::Reporters::RubyLspReporter
