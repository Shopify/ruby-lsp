# typed: strict
# frozen_string_literal: true

module Minitest
  module Reporters
    class RubyLspReporter < BaseReporter
      def initialize(options = {})
        # TODO
        super
      end

      def start
        # TODO
        super
      end

      def before_test(test)
        # TODO
        super
      end

      def record(test)
        result = {
          classname: test.klass,
          file: test.source_location[0],
          line: test.source_location[1],
          time: test.time,
        }
        if (failure = test.failure)
          result[:failure] = {
            type: failure.class.name,
            message: failure.message, # TODO: truncate?
          }
        end

        if test.skipped?
          result[:skipped] = {
            message: "TODO: skip reason",
          }
        end

        puts result.to_json
        # TODO: flush IO after each?

        super # need?
      end

      def report
        # TODO
        super
      end
    end
  end
end
