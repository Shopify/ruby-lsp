# typed: strict
# frozen_string_literal: true

require "ruby_lsp/test_reporting"

module Minitest
  module Reporters
    class RubyLspReporter < BaseReporter
      def initialize(options = {})
        @reporting = RubyLsp::TestReporting.new
        super
      end

      def start
        # TODO
        super
      end

      def before_test(test)
        @reporting.before_test(class_name: test.class)
        super
      end

      def record(test)
        if test.passed?
          record_pass(test)
        elsif test.skipped?
          record_skip(test)
        elsif test.failure
          record_fail(test)
        end

        super # need?
      end

      def record_pass(test)
        result = {
          class_name: test.klass,
          file: test.source_location[0],
          line: test.source_location[1],
        }
        @reporting.record_pass(**result)
      end

      def record_skip(test)
        result = {
          class_name: test.klass,
          file: test.source_location[0],
          line: test.source_location[1],
        }
        @reporting.record_skip(**result)
      end

      def record_fail(test)
        result = {
          class_name: test.klass,
          type: test.failure.class.name,
          message: test.failure.message, # TODO: truncate?
          file: test.source_location[0],
          line: test.source_location[1],
        }
        @reporting.record_fail(**result)
      end

      def report
        # TODO
        super
      end
    end
  end
end
