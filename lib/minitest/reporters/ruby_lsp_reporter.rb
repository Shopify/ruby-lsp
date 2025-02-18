# typed: strict
# frozen_string_literal: true

require "ruby_lsp/test_reporter"

# NOTE: minitest-reporters mentioned an API change between minitest 5.10 and 5.11, so we should verify:
# https://github.com/minitest-reporters/minitest-reporters/blob/265ff4b40d5827e84d7e902b808fbee860b61221/lib/minitest/reporters/base_reporter.rb#L82-L91

module Minitest
  module Reporters
    # TODO: consider if minitest-reporrters should be a dependency of ruby-lsp
    class RubyLspReporter < ::Minitest::Reporters::BaseReporter
      extend T::Sig

      sig { void }
      def initialize
        @reporting = T.let(RubyLsp::TestReporter.new, RubyLsp::TestReporter)
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
