# typed: strict
# frozen_string_literal: true

require_relative "test_reporter"
require "ruby_indexer/lib/ruby_indexer/uri"

require "minitest"

module Minitest
  module Reporters
    class RubyLspReporter < ::Minitest::AbstractReporter
      class << self
        #: (Hash[untyped, untyped]) -> void
        def minitest_plugin_init(_options)
          Minitest.reporter.reporters = [RubyLspReporter.new]
        end
      end

      #: (singleton(Minitest::Test) test_class, String method_name) -> void
      def prerecord(test_class, method_name)
        uri = uri_from_test_class(test_class, method_name)
        return unless uri

        RubyLsp::TestReporter.start_test(
          id: "#{test_class.name}##{method_name}",
          uri: uri,
        )
      end

      #: (Minitest::Result result) -> void
      def record(result)
        if result.error?
          record_error(result)
        elsif result.passed?
          record_pass(result)
        elsif result.skipped?
          record_skip(result)
        elsif result.failure
          record_fail(result)
        end
      end

      private

      #: (Minitest::Result result) -> void
      def record_pass(result)
        RubyLsp::TestReporter.record_pass(
          id: id_from_result(result),
          uri: uri_from_result(result),
        )
      end

      #: (Minitest::Result result) -> void
      def record_skip(result)
        RubyLsp::TestReporter.record_skip(
          id: id_from_result(result),
          message: result.failure.message,
          uri: uri_from_result(result),
        )
      end

      #: (Minitest::Result result) -> void
      def record_fail(result)
        RubyLsp::TestReporter.record_fail(
          id: id_from_result(result),
          message: result.failure.message,
          uri: uri_from_result(result),
        )
      end

      #: (Minitest::Result result) -> void
      def record_error(result)
        RubyLsp::TestReporter.record_error(
          id: id_from_result(result),
          uri: uri_from_result(result),
          message: result.failures.first.message,
        )
      end

      #: (Minitest::Result result) -> String
      def id_from_result(result)
        "#{result.klass}##{result.name}"
      end

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
