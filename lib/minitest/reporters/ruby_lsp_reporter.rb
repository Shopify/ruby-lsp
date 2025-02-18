# typed: strict
# frozen_string_literal: true

require "ruby_lsp/test_reporting"

module Minitest
  module Reporters
    class RubyLspReporter < ::Minitest::Reporters::BaseReporter
      extend T::Sig

      sig { void }
      def initialize
        @reporting = T.let(RubyLsp::TestReporting.new, RubyLsp::TestReporting)
        super
      end

      sig { params(test: Minitest::Test).void }
      def before_test(test)
        @reporting.before_test(
          id: id_from_test(test),
          file: file_for_class_name(test),
        )
        super
      end

      sig { params(test: Minitest::Test).void }
      def after_test(test)
        @reporting.after_test(
          id: id_from_test(test),
          file: file_for_class_name(test),
        )
        super
      end

      sig { params(test: Minitest::Result).void }
      def record(test)
        super

        # This follows the pattern used by Minitest::Reporters::DefaultReporter
        on_record(test)
      end

      sig { params(test: Minitest::Result).void }
      def on_record(test)
        if test.passed?
          record_pass(test)
        elsif test.skipped?
          record_skip(test)
        elsif test.failure
          record_fail(test)
        end
      end

      sig { params(result: Minitest::Result).void }
      def record_pass(result)
        info = {
          id: id_from_result(result),
          file: result.source_location[0],
        }
        @reporting.record_pass(**info)
      end

      sig { params(result: Minitest::Result).void }
      def record_skip(result)
        info = {
          id: id_from_result(result),
          message: result.failure.message,
          file: result.source_location[0],
        }
        @reporting.record_skip(**info)
      end

      sig { params(result: Minitest::Result).void }
      def record_fail(result)
        info = {
          id: id_from_result(result),
          type: result.failure.class.name,
          message: result.failure.message,
          file: result.source_location[0],
        }
        @reporting.record_fail(**info)
      end

      private

      sig { params(test: Minitest::Test).returns(String) }
      def id_from_test(test)
        [test.class.name, test.name].join("#")
      end

      sig { params(result: Minitest::Result).returns(String) }
      def id_from_result(result)
        [result.name, result.klass].join("#")
      end

      sig { params(test: Minitest::Test).returns(String) }
      def file_for_class_name(test)
        T.must(Kernel.const_source_location(test.class_name)).first
      end
    end
  end
end
